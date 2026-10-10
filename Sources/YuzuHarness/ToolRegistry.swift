import Foundation

public struct MaterializedTools: Sendable {
    public var definitions: [ToolDefinition]
    public var allowedNames: Set<String>
    public let projectPath: String

    private static let registeredBuiltinNames: Set<String> = ["read", "glob", "grep"]

    public func settle(call: ToolCall) -> String {
        guard allowedNames.contains(call.name) else {
            if Self.registeredBuiltinNames.contains(call.name) {
                return "Stale tool call"
            }
            return "Unknown tool"
        }
        let agent = Agent.build
        let resource = call.name == "bash" ? (stringField(call.arguments, key: "command") ?? "*") : "*"
        switch agent.effect(action: call.name, resource: resource) {
        case .deny:
            return "Permission denied"
        case .ask:
            return "Permission required"
        case .allow:
            return BuiltinTools.execute(name: call.name, arguments: call.arguments, projectPath: projectPath)
        }
    }
}

public enum ToolRegistry {
    private static let builtins: [ToolDefinition] = [
        BuiltinTools.read,
        BuiltinTools.glob,
        BuiltinTools.grep,
    ]

    public static func materialize(
        agent: Agent,
        projectPath: String,
        onlyNames: Set<String>? = nil
    ) -> MaterializedTools {
        var definitions: [ToolDefinition] = []
        var allowed = Set<String>()
        for tool in builtins {
            if onlyNames != nil, !(onlyNames?.contains(tool.name) ?? false) {
                continue
            }
            let action = tool.name
            if agent.effect(action: action, resource: "*") == .allow {
                definitions.append(tool)
                allowed.insert(tool.name)
            }
        }
        return MaterializedTools(definitions: definitions, allowedNames: allowed, projectPath: projectPath)
    }
}

private func stringField(_ value: JSONValue, key: String) -> String? {
    guard case .object(let object) = value,
          case .string(let string)? = object[key] else {
        return nil
    }
    return string
}
