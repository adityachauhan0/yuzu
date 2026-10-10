import Foundation
import os

/// How the Code composer treats permission asks.
/// Workspace Read asks before edits and shell. Workspace Write allows file edits and still asks for shell.
/// YOLO allows every ask. An agent deny still wins, so Plan stays read-only.
public enum PermissionPosture: Int, Sendable, Equatable {
    case workspaceWrite = 0
    case workspaceRead = 1
    case yolo = 2

    public var label: String {
        switch self {
        case .workspaceRead: "Workspace Read"
        case .workspaceWrite: "Workspace Write"
        case .yolo: "YOLO"
        }
    }

    public var next: PermissionPosture {
        switch self {
        case .workspaceRead: .workspaceWrite
        case .workspaceWrite: .yolo
        case .yolo: .workspaceRead
        }
    }

    public init(manualPressed: Bool) {
        self = manualPressed ? .workspaceRead : .workspaceWrite
    }
}

public enum PermissionEvaluator {
    public static let unknownAgentDenyAll: [PermissionRule] = [
        PermissionRule(action: "*", resource: "*", effect: .deny),
    ]

    /// Walks `rules` last-to-first; last wildcard match wins. Empty ruleset → `ask`.
    public static func evaluateRules(
        _ rules: [PermissionRule],
        action: String,
        resource: String
    ) -> PermissionEffect {
        for rule in rules.reversed() {
            if wildcardMatch(rule.action, action), wildcardMatch(rule.resource, resource) {
                return rule.effect
            }
        }
        return .ask
    }

    /// Agent rules first; saved allows second. Agent deny cannot be overridden.
    /// Workspace Write allows `edit`. YOLO allows every remaining ask.
    public static func effect(
        agentID: String,
        action: String,
        resource: String,
        savedAllows: [PermissionRule],
        manualPressed: Bool,
        posture: PermissionPosture? = nil
    ) -> PermissionEffect {
        let posture = posture ?? PermissionPosture(manualPressed: manualPressed)
        let agentRules = AgentCatalog.rules(for: agentID)
        let agentEffect = evaluateRules(agentRules, action: action, resource: resource)
        if agentEffect == .deny {
            return .deny
        }

        if evaluateRules(savedAllows, action: action, resource: resource) == .allow {
            return .allow
        }

        switch posture {
        case .yolo:
            return .allow
        case .workspaceWrite:
            if action == "edit" {
                return .allow
            }
        case .workspaceRead:
            break
        }

        return agentEffect
    }

    public static func wildcardMatch(_ pattern: String, _ value: String) -> Bool {
        if pattern == "*" {
            return true
        }
        if pattern.hasSuffix("*"), pattern.filter({ $0 == "*" }).count == 1 {
            let prefix = String(pattern.dropLast())
            return value.hasPrefix(prefix)
        }
        return pattern == value
    }
}

public enum AgentCatalog {
    private static let customAgentsLock = OSAllocatedUnfairLock(initialState: [String: Agent]())

    public static func registerForTests(_ agent: Agent) {
        customAgentsLock.withLock { $0[agent.id] = agent }
    }

    public static func resetCustomAgentsForTests() {
        customAgentsLock.withLock { $0 = [:] }
    }

    public static func agent(id: String) -> Agent? {
        if let custom = customAgentsLock.withLock({ $0[id] }) {
            return custom
        }
        switch id {
        case Agent.build.id:
            return .build
        case Agent.plan.id:
            return .plan
        default:
            return nil
        }
    }

    public static func rules(for agentID: String) -> [PermissionRule] {
        agent(id: agentID)?.rules ?? PermissionEvaluator.unknownAgentDenyAll
    }
}

public enum PermissionGate {
    public static let denialMessage = "Permission denied"

    public static func permissionAction(for toolName: String, arguments: JSONValue? = nil) -> String? {
        if toolName == "read_resource", let arguments {
            if let uri = stringField(arguments, key: "uri"),
               let server = MCPHub.shared.serverName(forResourceURI: uri) {
                return "mcp:\(server)"
            }
            return "mcp:*"
        }
        switch toolName {
        case "read":
            return "read"
        case "glob":
            return "glob"
        case "grep":
            return "grep"
        case "write", "edit":
            return "edit"
        case "bash":
            return "bash"
        case "webfetch":
            return "webfetch"
        case "mcp":
            return "mcp"
        case "skill":
            return "skill"
        case "question":
            return nil
        case "task":
            return "task"
        case "read_resource":
            return nil
        default:
            if let action = MCPHub.shared.permissionAction(forHarnessName: toolName) {
                return action
            }
            return nil
        }
    }

    public static func resources(toolName: String, arguments: JSONValue) -> [String] {
        switch toolName {
        case "write", "edit":
            return [stringField(arguments, key: "path") ?? "*"]
        case "bash":
            return [stringField(arguments, key: "command") ?? "*"]
        case "webfetch":
            return [stringField(arguments, key: "url") ?? "*"]
        case "mcp":
            return [stringField(arguments, key: "name") ?? "*"]
        case "skill":
            return [stringField(arguments, key: "name") ?? "*"]
        case "task":
            return [stringField(arguments, key: "agent") ?? "*"]
        case "read_resource":
            if let server = MCPHub.shared.serverName(forResourceURI: stringField(arguments, key: "uri")) {
                return [server]
            }
            return ["*"]
        default:
            if let resource = MCPHub.shared.mcpResource(forHarnessName: toolName) {
                return [resource]
            }
            return ["*"]
        }
    }

    public static func isWhollyDenied(agentID: String, action: String) -> Bool {
        PermissionEvaluator.effect(
            agentID: agentID,
            action: action,
            resource: "*",
            savedAllows: [],
            manualPressed: true
        ) == .deny
    }
}

public struct PermissionRequestRecord: Sendable, Equatable {
    public var id: String
    public var sessionID: String
    public var agentID: String
    public var action: String
    public var resources: [String]
    public var toolCallID: String
    public var toolName: String
}

public struct HarnessEventRecord: Sendable, Equatable {
    public var sessionID: String
    public var name: String
    public var permissionRequestID: String?

    public init(sessionID: String, name: String, permissionRequestID: String?) {
        self.sessionID = sessionID
        self.name = name
        self.permissionRequestID = permissionRequestID
    }
}

func stringField(_ value: JSONValue, key: String) -> String? {
    guard case .object(let object) = value,
          case .string(let string)? = object[key] else {
        return nil
    }
    return string
}
