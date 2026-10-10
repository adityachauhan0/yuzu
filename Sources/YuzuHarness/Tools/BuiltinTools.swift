import Foundation

enum BuiltinTools {
    static let read = ToolDefinition(
        name: "read",
        description: "Read a text file inside the project.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object([
                    "type": .string("string"),
                    "description": .string("Relative path from the project root"),
                ]),
            ]),
            "required": .array([.string("path")]),
        ])
    )

    static let glob = ToolDefinition(
        name: "glob",
        description: "Find file names matching a glob pattern inside the project.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "pattern": .object([
                    "type": .string("string"),
                    "description": .string("Glob pattern"),
                ]),
            ]),
            "required": .array([.string("pattern")]),
        ])
    )

    static let edit = ToolDefinition(
        name: "edit",
        description: "Replace one exact string in a project file.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object([
                    "type": .string("string"),
                    "description": .string("Relative path from the project root"),
                ]),
                "old_string": .object([
                    "type": .string("string"),
                    "description": .string("Text to replace"),
                ]),
                "new_string": .object([
                    "type": .string("string"),
                    "description": .string("Replacement text"),
                ]),
            ]),
            "required": .array([.string("path"), .string("old_string"), .string("new_string")]),
        ])
    )

    static let bash = ToolDefinition(
        name: "bash",
        description: "Run one shell command in the project directory.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "command": .object([
                    "type": .string("string"),
                    "description": .string("Shell command"),
                ]),
            ]),
            "required": .array([.string("command")]),
        ])
    )

    static let grep = ToolDefinition(
        name: "grep",
        description: "Search file contents inside the project.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "pattern": .object([
                    "type": .string("string"),
                    "description": .string("Search pattern"),
                ]),
                "path": .object([
                    "type": .string("string"),
                    "description": .string("Directory or file path relative to the project"),
                ]),
            ]),
            "required": .array([.string("pattern")]),
        ])
    )

    static func execute(name: String, arguments: JSONValue, projectPath: String) -> String {
        switch name {
        case "read":
            return executeRead(arguments: arguments, projectPath: projectPath)
        case "glob":
            return executeGlob(arguments: arguments, projectPath: projectPath)
        case "grep":
            return executeGrep(arguments: arguments, projectPath: projectPath)
        case "edit":
            return "Edited \(stringArg(arguments, key: "path") ?? "file")"
        case "bash":
            return "Ran: \(stringArg(arguments, key: "command") ?? "")"
        default:
            return "Unknown tool"
        }
    }

    private static func stringArg(_ arguments: JSONValue, key: String) -> String? {
        guard case .object(let object) = arguments,
              case .string(let value)? = object[key] else {
            return nil
        }
        return value
    }

    private static func executeRead(arguments: JSONValue, projectPath: String) -> String {
        guard let path = stringArg(arguments, key: "path") else {
            return "Error: missing path"
        }
        do {
            let url = try ProjectPaths.resolve(path: path, in: projectPath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return "Error: file not found"
            }
            let data = try Data(contentsOf: url)
            if let text = String(data: data, encoding: .utf8) {
                return text
            }
            return "Error: file is not valid UTF-8 text"
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    private static func executeGlob(arguments: JSONValue, projectPath: String) -> String {
        guard let pattern = stringArg(arguments, key: "pattern") else {
            return "Error: missing pattern"
        }
        let root = ProjectPaths.projectRootURL(path: projectPath)
        let rootPath = root.path
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ""
        }
        var matches: [String] = []
        let regex = globToRegex(pattern)
        for case let fileURL as URL in enumerator {
            let relative = String(fileURL.path.dropFirst(rootPath.count + 1))
            if regex.firstMatch(in: relative, range: NSRange(relative.startIndex..., in: relative)) != nil {
                matches.append(relative)
            }
        }
        return matches.sorted().joined(separator: "\n")
    }

    private static func executeGrep(arguments: JSONValue, projectPath: String) -> String {
        guard let pattern = stringArg(arguments, key: "pattern") else {
            return "Error: missing pattern"
        }
        let searchPath = stringArg(arguments, key: "path") ?? "."
        do {
            let url = try ProjectPaths.resolve(path: searchPath, in: projectPath)
            var lines: [String] = []
            if url.hasDirectoryPath {
                let rootPath = ProjectPaths.projectRootURL(path: projectPath).path
                guard let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    return ""
                }
                for case let fileURL as URL in enumerator {
                    guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                          values.isRegularFile == true else { continue }
                    let relative = String(fileURL.path.dropFirst(rootPath.count + 1))
                    if let fileLines = grepFile(at: fileURL, pattern: pattern, relativePath: relative) {
                        lines.append(contentsOf: fileLines)
                    }
                }
            } else {
                let rootPath = ProjectPaths.projectRootURL(path: projectPath).path
                let relative = String(url.path.dropFirst(rootPath.count + 1))
                if let fileLines = grepFile(at: url, pattern: pattern, relativePath: relative) {
                    lines.append(contentsOf: fileLines)
                }
            }
            return lines.joined(separator: "\n")
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    private static func grepFile(at url: URL, pattern: String, relativePath: String) -> [String]? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        var result: [String] = []
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if line.contains(pattern) {
                result.append("\(relativePath):\(index + 1):\(line)")
            }
        }
        return result
    }

    private static func globToRegex(_ pattern: String) -> NSRegularExpression {
        var regex = "^"
        for char in pattern {
            switch char {
            case "*":
                regex += ".*"
            case "?":
                regex += "."
            case ".":
                regex += "\\."
            default:
                regex.append(char)
            }
        }
        regex += "$"
        return (try? NSRegularExpression(pattern: regex)) ?? NSRegularExpression()
    }
}
