import Foundation

public enum ContextSourceKey: String, Sendable, Codable, CaseIterable {
    case instructions = "core/instructions"
    case workspace = "core/workspace"
    case date = "core/date"
}

public struct EpochRecord: Sendable, Equatable {
    public var sessionID: String
    public var epochID: String
    public var baselineText: String
    public var snapshotsJSON: String
}

public struct ContextBoundaryResult: Sendable, Equatable {
    public var blocked: Bool
    public var baselinePrepended: Bool
}

/// Loads and reconciles context sources at provider-turn boundaries.
public struct ContextCoordinator: Sendable {
    public static let instructionsCap = 32 * 1024

    public var loadInstructions: @Sendable (String) throws -> String?
    public var loadUserInstructions: @Sendable () throws -> String?

    public init(
        loadInstructions: @escaping @Sendable (String) throws -> String? = ContextCoordinator.defaultLoadInstructions,
        loadUserInstructions: @escaping @Sendable () throws -> String? = { nil }
    ) {
        self.loadInstructions = loadInstructions
        self.loadUserInstructions = loadUserInstructions
    }

    public static func defaultLoadInstructions(projectPath: String) throws -> String? {
        try InstructionsFiles.aggregate(projectPath: projectPath, readFile: defaultReadFile)
    }

    private static func defaultReadFile(_ url: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }

    public func reconcile(
        store: HarnessStore,
        sessionID: String,
        epochID: String,
        projectPath: String
    ) throws -> ContextBoundaryResult {
        let existing = try store.epochRecord(sessionID: sessionID, epochID: epochID)
        let loaded: [ContextSourceKey: String]
        do {
            loaded = try loadSources(projectPath: projectPath, fallback: existing)
        } catch {
            if existing == nil {
                return ContextBoundaryResult(blocked: true, baselinePrepended: false)
            }
            return ContextBoundaryResult(blocked: false, baselinePrepended: false)
        }

        if existing == nil {
            let baseline = renderBaseline(sources: loaded)
            let snapshots = encodeSnapshots(loaded)
            try store.insertEpoch(
                EpochRecord(
                    sessionID: sessionID,
                    epochID: epochID,
                    baselineText: baseline,
                    snapshotsJSON: snapshots
                )
            )
            return ContextBoundaryResult(blocked: false, baselinePrepended: false)
        }

        let previous = decodeSnapshots(existing!.snapshotsJSON)
        var updates: [String] = []

        for key in ContextSourceKey.allCases {
            let newValue = loaded[key] ?? ""
            let oldValue = previous[key.rawValue] ?? ""
            if newValue != oldValue {
                if let text = renderUpdate(key: key, newValue: newValue) {
                    updates.append(text)
                }
            }
        }

        if !updates.isEmpty {
            let combined = updates.joined(separator: "\n\n")
            try store.appendMessage(sessionID: sessionID, message: .system(combined))
            let merged = previous.merging(
                loaded.mapKeys { $0.rawValue },
                uniquingKeysWith: { _, new in new }
            )
            try store.updateEpochSnapshots(
                sessionID: sessionID,
                epochID: epochID,
                snapshotsJSON: encodeSnapshotsMap(merged)
            )
        }

        return ContextBoundaryResult(blocked: false, baselinePrepended: false)
    }

    public func baselineSystemText(
        store: HarnessStore,
        sessionID: String,
        epochID: String
    ) throws -> String? {
        try store.epochRecord(sessionID: sessionID, epochID: epochID)?.baselineText
    }

    public func providerDelta(
        store: HarnessStore,
        sessionID: String,
        session: SessionRecord
    ) throws -> [StoredMessage] {
        let allMessages = try store.messages(sessionID: sessionID)
        var delta = Array(allMessages.dropFirst(session.modelMessageCursor))
        guard let baseline = try baselineSystemText(
            store: store,
            sessionID: sessionID,
            epochID: session.epochID
        ), !baseline.isEmpty else {
            return delta
        }
        guard shouldPrependBaseline(delta: delta) else {
            return delta
        }
        delta.insert(.system(baseline), at: 0)
        return delta
    }

    private func shouldPrependBaseline(delta: [StoredMessage]) -> Bool {
        guard let last = delta.last else { return false }
        return last.role != .tool
    }

    private func loadSources(
        projectPath: String,
        fallback: EpochRecord?
    ) throws -> [ContextSourceKey: String] {
        let previous = fallback.map { decodeSnapshots($0.snapshotsJSON) } ?? [:]
        var map: [ContextSourceKey: String] = [:]

        do {
            if let instructions = try loadInstructions(projectPath) {
                map[.instructions] = capInstructions(instructions)
            } else if let saved = previous[ContextSourceKey.instructions.rawValue] {
                map[.instructions] = saved
            }
        } catch {
            if let saved = previous[ContextSourceKey.instructions.rawValue] {
                map[.instructions] = saved
            } else {
                throw error
            }
        }

        do {
            if let user = try loadUserInstructions() {
                let existing = map[.instructions] ?? ""
                let combined = existing.isEmpty ? user : existing + "\n\n" + user
                map[.instructions] = capInstructions(combined)
            }
        } catch {
            if map[.instructions] == nil, let saved = previous[ContextSourceKey.instructions.rawValue] {
                map[.instructions] = saved
            }
        }

        map[.workspace] = WorkspaceSource.render(projectPath: projectPath)
        map[.date] = DateSource.render()
        return map
    }

    private func capInstructions(_ text: String) -> String {
        if text.utf8.count <= Self.instructionsCap {
            return text
        }
        var result = ""
        for character in text {
            let next = result + String(character)
            if next.utf8.count > Self.instructionsCap { break }
            result = next
        }
        return result
    }

    private func renderBaseline(sources: [ContextSourceKey: String]) -> String {
        var parts: [String] = []
        if let instructions = sources[.instructions], !instructions.isEmpty {
            parts.append(instructions)
        }
        if let workspace = sources[.workspace], !workspace.isEmpty {
            parts.append(workspace)
        }
        if let date = sources[.date], !date.isEmpty {
            parts.append(date)
        }
        return parts.joined(separator: "\n\n")
    }

    private func renderUpdate(key: ContextSourceKey, newValue: String) -> String? {
        switch key {
        case .instructions:
            return """
            <file path="YUZU.md">
            \(newValue)
            </file>
            """
        case .workspace:
            return newValue
        case .date:
            return newValue
        }
    }

    private func encodeSnapshots(_ sources: [ContextSourceKey: String]) -> String {
        encodeSnapshotsMap(sources.mapKeys { $0.rawValue })
    }

    private func encodeSnapshotsMap(_ map: [String: String]) -> String {
        let data = (try? JSONEncoder().encode(map)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private func decodeSnapshots(_ json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return map
    }
}

enum InstructionsFiles {
    static func aggregate(
        projectPath: String,
        readFile: (URL) throws -> String?
    ) throws -> String? {
        let root = URL(fileURLWithPath: projectPath, isDirectory: true).standardizedFileURL
        var directories: [URL] = []
        var current = root
        directories.append(current)
        while !isWorktreeRoot(current) {
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
            directories.append(current)
        }

        var segments: [String] = []
        for directory in directories.reversed() {
            let yuzu = directory.appendingPathComponent("YUZU.md")
            if let text = try readFile(yuzu), !text.isEmpty {
                segments.append(text)
                continue
            }
            let agents = directory.appendingPathComponent("AGENTS.md")
            if let text = try readFile(agents), !text.isEmpty {
                segments.append(text)
            }
        }

        guard !segments.isEmpty else { return nil }
        return segments.joined(separator: "\n\n")
    }

    private static func isWorktreeRoot(_ url: URL) -> Bool {
        let git = url.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: git.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return true
        }
        return false
    }
}

enum WorkspaceSource {
    static func render(projectPath: String) -> String {
        var lines = ["Project: \(projectPath)"]
        if let branch = currentGitBranch(projectPath: projectPath) {
            lines.append("Branch: \(branch)")
        }
        return lines.joined(separator: "\n")
    }

    private static func currentGitBranch(projectPath: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", projectPath, "rev-parse", "--abbrev-ref", "HEAD"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let name = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        } catch {
            return nil
        }
    }
}

enum DateSource {
    static func render() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return "Date: \(formatter.string(from: Date()))"
    }
}

private extension Dictionary {
    func mapKeys<T: Hashable>(_ transform: (Key) throws -> T) rethrows -> [T: Value] {
        var result: [T: Value] = [:]
        for (key, value) in self {
            result[try transform(key)] = value
        }
        return result
    }
}
