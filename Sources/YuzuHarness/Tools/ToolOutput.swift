import Foundation

public enum ToolOutput {
    /// Production cap for model-visible tool output. Tests may lower this via `characterCapForTesting`.
    public static let productionCharacterCap = 32_000

    nonisolated(unsafe) public static var characterCapForTesting: Int?

    static var effectiveCharacterCap: Int {
        characterCapForTesting ?? productionCharacterCap
    }

    /// If `raw` exceeds the cap, writes the full text under Application Support and returns a short message plus the path.
    public static func project(raw: String, sessionID: String, callID: String) -> String {
        let cap = effectiveCharacterCap
        guard raw.count > cap else { return raw }

        let directory = spillDirectory(sessionID: sessionID, callID: callID)
        do {
            try FileManager.default.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
            try raw.write(to: directory, atomically: true, encoding: .utf8)
        } catch {
            let prefix = String(raw.prefix(cap))
            return "\(prefix)\n\nError: could not write full tool output (\(error.localizedDescription))"
        }

        let prefix = String(raw.prefix(cap))
        return "\(prefix)\n\n… output truncated (\(raw.count) characters). Full output: \(directory.path)"
    }

    public static func spillDirectory(sessionID: String, callID: String) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support
            .appendingPathComponent("tool-output", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
            .appendingPathComponent(callID, isDirectory: false)
    }
}
