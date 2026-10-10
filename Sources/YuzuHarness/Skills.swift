import Foundation

public struct SkillRecord: Sendable, Equatable {
    public var name: String
    public var description: String
    public var body: String
    public var directoryPath: String
    public var slash: Bool

    public init(name: String, description: String, body: String, directoryPath: String, slash: Bool = false) {
        self.name = name
        self.description = description
        self.body = body
        self.directoryPath = directoryPath
        self.slash = slash
    }
}

public enum SkillCatalog {
    public static let customizeYuzuUniqueBodyMarker =
        "This sentence must never appear in skill guidance baseline text."

    private static let embeddedSkillNames = ["customize-yuzu"]

    public static func userSkillsRoot() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Application Support/Yuzu/skills", isDirectory: true)
    }

    public static func projectSkillsRoot(projectPath: String) -> URL {
        URL(fileURLWithPath: projectPath, isDirectory: true)
            .appendingPathComponent(".yuzu/skills", isDirectory: true)
    }

    public static func discover(projectPath: String) -> [SkillRecord] {
        var byName: [String: SkillRecord] = [:]
        let orderedSources: [URL] = [
            embeddedSkillsRoot(),
            userSkillsRoot(),
            projectSkillsRoot(projectPath: projectPath),
        ]
        for source in orderedSources {
            let found = discover(in: source, isEmbeddedRoot: source == embeddedSkillsRoot())
            for skill in found {
                byName[skill.name] = skill
            }
        }
        return byName.values.sorted { $0.name < $1.name }
    }

    public static func allowedSkills(rules: [PermissionRule], projectPath: String) -> [SkillRecord] {
        discover(projectPath: projectPath).filter { skill in
            PermissionEvaluator.evaluateRules(rules, action: "skill", resource: skill.name) != .deny
        }
    }

    public static func allowedSkills(agentID: String, projectPath: String) -> [SkillRecord] {
        allowedSkills(rules: AgentCatalog.rules(for: agentID), projectPath: projectPath)
    }

    public static func renderGuidance(rules: [PermissionRule], projectPath: String) -> String {
        if PermissionEvaluator.evaluateRules(rules, action: "skill", resource: "*") == .deny {
            return ""
        }
        let skills = allowedSkills(rules: rules, projectPath: projectPath)
        if skills.isEmpty {
            return "No skills are currently available."
        }
        var lines = [
            "When a task matches one of the skills below, call the `skill` tool with its `name`.",
            "",
            "Available skills:",
        ]
        for skill in skills {
            lines.append("- \(skill.name): \(skill.description)")
        }
        return lines.joined(separator: "\n")
    }

    public static func renderGuidance(agentID: String, projectPath: String) -> String {
        renderGuidance(rules: AgentCatalog.rules(for: agentID), projectPath: projectPath)
    }

    public static func skillToolResult(name: String, projectPath: String) -> String {
        guard let skill = discover(projectPath: projectPath).first(where: { $0.name == name }) else {
            return "Error: skill not found: \(name)"
        }
        let siblings = siblingFilePaths(directory: skill.directoryPath, limit: 10)
        let filesBlock = siblings.isEmpty ? "" : "\n<skill_files>\n\(siblings.joined(separator: "\n"))\n</skill_files>"
        return """
        <skill_content name="\(skill.name)">
        # Skill: \(skill.name)
        \(skill.body)
        Base directory: \(skill.directoryPath)\(filesBlock)
        </skill_content>
        """
    }

    @discardableResult
    public static func createProjectSkill(
        projectPath: String,
        name: String,
        description: String
    ) throws -> URL {
        let directory = projectSkillsRoot(projectPath: projectPath).appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("SKILL.md")
        let contents = """
        ---
        name: \(name)
        description: \(description)
        ---

        """
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    private static func embeddedSkillsRoot() -> URL {
        if let url = Bundle.module.url(forResource: "EmbeddedSkills", withExtension: nil) {
            return url
        }
        return Bundle.module.resourceURL?.appendingPathComponent("EmbeddedSkills", isDirectory: true)
            ?? Bundle.module.bundleURL.appendingPathComponent("EmbeddedSkills", isDirectory: true)
    }

    private static func discover(in root: URL, isEmbeddedRoot: Bool) -> [SkillRecord] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        var results: [SkillRecord] = []

        if let topMarkdown = topLevelMarkdown(in: root) {
            for file in topMarkdown {
                if let skill = parseSkillFile(file, nameOverride: nil, isRootFile: true) {
                    results.append(skill)
                }
            }
        }

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return results
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent == "SKILL.md" else { continue }
            let parent = fileURL.deletingLastPathComponent()
            if parent.standardizedFileURL == root.standardizedFileURL { continue }
            if let skill = parseSkillFile(fileURL, nameOverride: nil, isRootFile: false) {
                results.append(skill)
            }
        }

        if isEmbeddedRoot, results.isEmpty {
            for name in embeddedSkillNames {
                let bundled = root.appendingPathComponent(name).appendingPathComponent("SKILL.md")
                if let skill = parseSkillFile(bundled, nameOverride: name, isRootFile: false) {
                    results.append(skill)
                }
            }
        }

        return results
    }

    private static func topLevelMarkdown(in root: URL) -> [URL]? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        return contents.filter { $0.pathExtension.lowercased() == "md" }
    }

    private static func parseSkillFile(_ url: URL, nameOverride: String?, isRootFile: Bool) -> SkillRecord? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let parsed = SkillFrontmatter.parse(text)
        let directory = url.deletingLastPathComponent().path
        let basename = url.deletingPathExtension().lastPathComponent
        let name: String?
        if let override = nameOverride {
            name = override
        } else if let frontName = parsed.frontmatter["name"], !frontName.isEmpty {
            name = frontName
        } else if isRootFile {
            name = basename
        } else {
            name = nil
        }
        guard let resolvedName = name else { return nil }
        let description = parsed.frontmatter["description"] ?? ""
        let slash = parsed.frontmatter["slash"]?.lowercased() == "true"
        return SkillRecord(
            name: resolvedName,
            description: description,
            body: parsed.body.trimmingCharacters(in: .whitespacesAndNewlines),
            directoryPath: directory,
            slash: slash
        )
    }

    private static func siblingFilePaths(directory: String, limit: Int) -> [String] {
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return entries
            .filter { $0.lastPathComponent != "SKILL.md" }
            .map(\.lastPathComponent)
            .sorted()
            .prefix(limit)
            .map { $0 }
    }
}

enum SkillFrontmatter {
    struct Parsed {
        var frontmatter: [String: String]
        var body: String
    }

    static func parse(_ text: String) -> Parsed {
        guard text.hasPrefix("---") else {
            return Parsed(frontmatter: [:], body: text)
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 2 else {
            return Parsed(frontmatter: [:], body: text)
        }
        var index = 1
        var map: [String: String] = [:]
        while index < lines.count {
            let line = lines[index]
            index += 1
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                let body = lines.dropFirst(index).joined(separator: "\n")
                return Parsed(frontmatter: map, body: body)
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            map[key] = value
        }
        return Parsed(frontmatter: [:], body: text)
    }
}

public enum ComposerCommands {
    /// `/name` plus an optional tail. Nil when the text is not a slash command.
    public static func command(_ text: String) -> (name: String, tail: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/"), trimmed.count > 1 else { return nil }
        let rest = trimmed.dropFirst()
        let parts = rest.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\n" })
        guard let first = parts.first else { return nil }
        let name = String(first)
        guard !name.isEmpty else { return nil }
        let tail = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return (name, tail)
    }

    /// A skill with `slash: true` admits its body. Other skills stay a tool call.
    public static func skillExpansion(text: String, skills: [SkillRecord]) -> String? {
        guard let command = command(text) else { return nil }
        guard let skill = skills.first(where: { $0.slash && $0.name == command.name }) else { return nil }
        if command.tail.isEmpty { return skill.body }
        return skill.body + "\n\n" + command.tail
    }
}
