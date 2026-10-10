import Foundation

/// Installs, lists, and removes MCP servers in Yuzu's `mcp.json`, then the session connects them.
public enum MCPTool {
    public static let definition = ToolDefinition(
        name: "mcp",
        description: """
        Install, list, or remove an MCP server for this harness. \
        Use this when the user asks to add a server such as DuckDuckGo. \
        action is install, list, or remove. \
        For DuckDuckGo, action install and name duckduckgo is enough: \
        the default command is npx with args -y and duckduckgo-mcp-server. \
        Pass command and args to install any other stdio server, or url for HTTP.
        """,
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "action": .object([
                    "type": .string("string"),
                    "description": .string("install, list, or remove"),
                ]),
                "name": .object([
                    "type": .string("string"),
                    "description": .string("Server name, such as duckduckgo"),
                ]),
                "command": .object([
                    "type": .string("string"),
                    "description": .string("Stdio executable. Defaults for duckduckgo."),
                ]),
                "args": .object([
                    "type": .string("array"),
                    "description": .string("Arguments for the command"),
                    "items": .object(["type": .string("string")]),
                ]),
                "url": .object([
                    "type": .string("string"),
                    "description": .string("HTTP server URL, instead of command"),
                ]),
            ]),
            "required": .array([.string("action")]),
        ])
    )

    public static let duckDuckGoCommand = "npx"
    public static let duckDuckGoArgs = ["-y", "duckduckgo-mcp-server"]

    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Yuzu", isDirectory: true).appendingPathComponent("mcp.json")
    }

    /// Writes one server into `mcp.json` and returns the saved document.
    public static func install(
        name: String,
        command: String?,
        args: [String],
        url: String?,
        at fileURL: URL
    ) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MCPConfigError.missingTransport("name") }
        var entries = read(fileURL)
        entries.removeAll { $0.name == trimmed }
        let config = try config(name: trimmed, command: command, args: args, url: url)
        entries.append(MCPConfigEntry(name: trimmed, enabled: true, config: config))
        let text = MCPConfig.encode(entries)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
        return text
    }

    public static func remove(name: String, at fileURL: URL) throws -> String {
        var entries = read(fileURL)
        entries.removeAll { $0.name == name }
        let text = MCPConfig.encode(entries)
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
        return text
    }

    public static func read(_ fileURL: URL) -> [MCPConfigEntry] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8),
              let entries = try? MCPConfig.parse(text) else { return [] }
        return entries
    }

    public static func config(name: String, command: String?, args: [String], url: String?) throws -> MCPServerConfig {
        if let url, !url.isEmpty {
            return MCPServerConfig(name: name, transport: .http(url: url, headers: [:]), timeout: 30)
        }
        let resolved = resolve(name: name, command: command, args: args)
        guard let command = resolved.command, !command.isEmpty else {
            throw MCPConfigError.missingTransport(name)
        }
        return MCPServerConfig(
            name: name,
            transport: .stdio(command: command, arguments: resolved.args, environment: [:]),
            timeout: 30
        )
    }

    public static func resolve(name: String, command: String?, args: [String]) -> (command: String?, args: [String]) {
        let key = name.lowercased().replacingOccurrences(of: " ", with: "")
        if (command == nil || command?.isEmpty == true), key == "duckduckgo" || key == "ddg" {
            return (duckDuckGoCommand, duckDuckGoArgs)
        }
        return (command, args)
    }

    public static func stringArgs(_ value: JSONValue) -> [String] {
        guard case .object(let fields) = value, case .array(let items)? = fields["args"] else { return [] }
        return items.compactMap { item in
            if case .string(let text) = item { return text }
            return nil
        }
    }
}
