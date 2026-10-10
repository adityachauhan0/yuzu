import Foundation

public enum AgentMode: String, Sendable, Equatable {
    case primary
    case subagent
    case all
}

public struct Agent: Sendable, Equatable {
    public var id: String
    public var mode: AgentMode
    public var steps: Int?
    public var rules: [PermissionRule]

    public init(
        id: String,
        mode: AgentMode = .all,
        steps: Int? = nil,
        rules: [PermissionRule] = Agent.buildRules
    ) {
        self.id = id
        self.mode = mode
        self.steps = steps
        self.rules = rules
    }

    public var allowsSubagent: Bool {
        mode == .subagent || mode == .all
    }

    public static let buildRules: [PermissionRule] = [
        PermissionRule(action: "read", resource: "*", effect: .allow),
        PermissionRule(action: "glob", resource: "*", effect: .allow),
        PermissionRule(action: "grep", resource: "*", effect: .allow),
        PermissionRule(action: "skill", resource: "*", effect: .allow),
        PermissionRule(action: "task", resource: "*", effect: .allow),
        PermissionRule(action: "edit", resource: "*", effect: .ask),
        PermissionRule(action: "bash", resource: "*", effect: .ask),
        PermissionRule(action: "mcp:*", resource: "*", effect: .ask),
    ]

    public static let build = Agent(id: "build", mode: .all)
    public static let plan = Agent(
        id: "plan",
        mode: .all,
        rules: [
            PermissionRule(action: "read", resource: "*", effect: .allow),
            PermissionRule(action: "glob", resource: "*", effect: .allow),
            PermissionRule(action: "grep", resource: "*", effect: .allow),
            PermissionRule(action: "edit", resource: "*", effect: .deny),
            PermissionRule(action: "bash", resource: "*", effect: .deny),
            PermissionRule(action: "skill", resource: "*", effect: .allow),
            PermissionRule(action: "mcp:*", resource: "*", effect: .ask),
        ]
    )

    public func effect(action: String, resource: String) -> PermissionEffect {
        PermissionEvaluator.evaluateRules(rules, action: action, resource: resource)
    }
}
