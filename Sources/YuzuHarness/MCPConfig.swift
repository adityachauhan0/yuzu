import Foundation

public struct MCPConfigEntry: Sendable, Equatable {
    public var name: String
    public var enabled: Bool
    public var config: MCPServerConfig

    public init(name: String, enabled: Bool, config: MCPServerConfig) {
        self.name = name
        self.enabled = enabled
        self.config = config
    }
}

public enum MCPConfigError: Error, Equatable {
    case invalidJSON
    case missingTransport(String)
}

/// Reads the settings document `{ "mcp_servers": { name: { enabled, command|url, ... } } }`.
public enum MCPConfig {
    public static func parse(_ json: String) throws -> [MCPConfigEntry] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = root["mcp_servers"] as? [String: Any]
        else {
            throw MCPConfigError.invalidJSON
        }

        var entries: [MCPConfigEntry] = []
        for name in servers.keys.sorted() {
            guard let body = servers[name] as? [String: Any] else {
                throw MCPConfigError.invalidJSON
            }
            let enabled = body["enabled"] as? Bool ?? true
            let timeout = (body["timeout"] as? NSNumber)?.doubleValue ?? 30
            if let url = body["url"] as? String, !url.isEmpty {
                let headers = stringMap(body["headers"])
                entries.append(
                    MCPConfigEntry(
                        name: name,
                        enabled: enabled,
                        config: MCPServerConfig(
                            name: name,
                            transport: .http(url: url, headers: headers),
                            timeout: timeout
                        )
                    )
                )
                continue
            }
            if let command = body["command"] as? String, !command.isEmpty {
                entries.append(
                    MCPConfigEntry(
                        name: name,
                        enabled: enabled,
                        config: MCPServerConfig(
                            name: name,
                            transport: .stdio(
                                command: command,
                                arguments: stringList(body["args"]),
                                environment: stringMap(body["env"])
                            ),
                            timeout: timeout
                        )
                    )
                )
                continue
            }
            if enabled {
                throw MCPConfigError.missingTransport(name)
            }
        }
        return entries
    }

    private static func stringList(_ value: Any?) -> [String] {
        (value as? [Any])?.compactMap { $0 as? String } ?? []
    }

    private static func stringMap(_ value: Any?) -> [String: String] {
        guard let raw = value as? [String: Any] else { return [:] }
        var map: [String: String] = [:]
        for (key, item) in raw {
            if let text = item as? String {
                map[key] = text
            }
        }
        return map
    }

    public static func encode(_ entries: [MCPConfigEntry]) -> String {
        var servers: [String: Any] = [:]
        for entry in entries {
            var body: [String: Any] = ["enabled": entry.enabled, "timeout": entry.config.timeout]
            switch entry.config.transport {
            case .stdio(let command, let arguments, let environment):
                body["command"] = command
                if !arguments.isEmpty { body["args"] = arguments }
                if !environment.isEmpty { body["env"] = environment }
            case .http(let url, let headers):
                body["url"] = url
                if !headers.isEmpty { body["headers"] = headers }
            }
            servers[entry.name] = body
        }
        let root: [String: Any] = ["mcp_servers": servers]
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{\n  \"mcp_servers\": {}\n}"
        }
        return text
    }
}
