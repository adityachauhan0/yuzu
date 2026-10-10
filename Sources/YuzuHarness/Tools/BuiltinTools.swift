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

    static let write = ToolDefinition(
        name: "write",
        description: "Create or replace a project file with the given body.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object([
                    "type": .string("string"),
                    "description": .string("Relative path from the project root"),
                ]),
                "body": .object([
                    "type": .string("string"),
                    "description": .string("Full file contents"),
                ]),
            ]),
            "required": .array([.string("path"), .string("body")]),
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
                "timeout": .object([
                    "type": .string("number"),
                    "description": .string("Timeout in seconds"),
                ]),
            ]),
            "required": .array([.string("command")]),
        ])
    )

    static let skill = ToolDefinition(
        name: "skill",
        description: "Load one skill body by name.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "name": .object([
                    "type": .string("string"),
                    "description": .string("Skill name"),
                ]),
            ]),
            "required": .array([.string("name")]),
        ])
    )

    static let task = ToolDefinition(
        name: "task",
        description: "Run a subagent with its own drain on the shared model.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "agent": .object([
                    "type": .string("string"),
                    "description": .string("Subagent id"),
                ]),
                "prompt": .object([
                    "type": .string("string"),
                    "description": .string("User prompt for the subagent"),
                ]),
            ]),
            "required": .array([.string("agent"), .string("prompt")]),
        ])
    )

    static let readResource = ToolDefinition(
        name: "read_resource",
        description: "Read one MCP server resource by URI.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "uri": .object([
                    "type": .string("string"),
                    "description": .string("Resource URI"),
                ]),
            ]),
            "required": .array([.string("uri")]),
        ])
    )

    static let webfetch = ToolDefinition(
        name: "webfetch",
        description: "Fetch one URL and return the page text.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "url": .object([
                    "type": .string("string"),
                    "description": .string("HTTP or HTTPS URL"),
                ]),
            ]),
            "required": .array([.string("url")]),
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
        case "write":
            return executeWrite(arguments: arguments, projectPath: projectPath)
        case "edit":
            return executeEdit(arguments: arguments, projectPath: projectPath)
        case "bash":
            return executeBash(arguments: arguments, projectPath: projectPath)
        case "skill":
            return executeSkill(arguments: arguments, projectPath: projectPath)
        case "webfetch":
            return executeWebFetch(arguments: arguments)
        default:
            return "Unknown tool"
        }
    }

    static func executeWebFetch(arguments: JSONValue) -> String {
        guard let urlText = stringArg(arguments, key: "url"),
              let url = URL(string: urlText),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return "Error: missing or invalid url"
        }
        let semaphore = DispatchSemaphore(value: 0)
        var payload = Data()
        var fetchError: Error?
        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            if let error {
                fetchError = error
            } else if let data {
                payload = data
            }
            semaphore.signal()
        }
        task.resume()
        if semaphore.wait(timeout: .now() + 30) == .timedOut {
            task.cancel()
            return "Error: request timed out"
        }
        if let fetchError {
            return "Error: \(fetchError.localizedDescription)"
        }
        if let text = String(data: payload, encoding: .utf8) {
            return text
        }
        return "Error: response is not valid UTF-8 text"
    }

    private static func executeWrite(arguments: JSONValue, projectPath: String) -> String {
        guard let path = stringArg(arguments, key: "path") else {
            return "Error: missing path"
        }
        guard let body = stringArg(arguments, key: "body") else {
            return "Error: missing body"
        }
        do {
            let url = try ProjectPaths.resolve(path: path, in: projectPath)
            let parent = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try body.write(to: url, atomically: true, encoding: .utf8)
            return "Wrote \(path)"
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    private static func executeEdit(arguments: JSONValue, projectPath: String) -> String {
        guard let path = stringArg(arguments, key: "path") else {
            return "Error: missing path"
        }
        guard let oldString = stringArg(arguments, key: "old_string") else {
            return "Error: missing old_string"
        }
        guard let newString = stringArg(arguments, key: "new_string") else {
            return "Error: missing new_string"
        }
        do {
            let url = try ProjectPaths.resolve(path: path, in: projectPath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return "Error: file not found"
            }
            let data = try Data(contentsOf: url)
            guard let content = String(data: data, encoding: .utf8) else {
                return "Error: file is not valid UTF-8 text"
            }
            let matchCount = content.components(separatedBy: oldString).count - 1
            if matchCount == 0 {
                return "Error: old_string not found in file"
            }
            if matchCount > 1 {
                return "Error: old_string appears \(matchCount) times; expected exactly one match"
            }
            let updated = content.replacingOccurrences(of: oldString, with: newString)
            try updated.write(to: url, atomically: true, encoding: .utf8)
            return "Edited \(path): replaced `\(oldString)` with `\(newString)`"
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    private static func executeBash(arguments: JSONValue, projectPath: String) -> String {
        guard let command = stringArg(arguments, key: "command") else {
            return "Error: missing command"
        }
        let timeout = numberArg(arguments, key: "timeout")
        let root = ProjectPaths.projectRootURL(path: projectPath).path
        return BashRunner.run(command: command, workingDirectory: root, timeoutSeconds: timeout)
    }

    private static func numberArg(_ arguments: JSONValue, key: String) -> Double? {
        guard case .object(let object) = arguments else { return nil }
        switch object[key] {
        case .number(let value):
            return value
        case .string(let text):
            return Double(text)
        default:
            return nil
        }
    }

    private static func stringArg(_ arguments: JSONValue, key: String) -> String? {
        guard case .object(let object) = arguments,
              case .string(let value)? = object[key] else {
            return nil
        }
        return value
    }

    private static func executeSkill(arguments: JSONValue, projectPath: String) -> String {
        guard let name = stringArg(arguments, key: "name") else {
            return "Error: missing name"
        }
        return SkillCatalog.skillToolResult(name: name, projectPath: projectPath)
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
