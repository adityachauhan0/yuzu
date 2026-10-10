import Foundation

public struct Agent: Sendable, Equatable {
    public var id: String
    public var steps: Int?
    public var rules: [PermissionRule]

    public init(id: String, steps: Int? = nil, rules: [PermissionRule] = Agent.buildRules) {
        self.id = id
        self.steps = steps
        self.rules = rules
    }

    public static let buildRules: [PermissionRule] = [
        PermissionRule(action: "read", resource: "*", effect: .allow),
        PermissionRule(action: "glob", resource: "*", effect: .allow),
        PermissionRule(action: "grep", resource: "*", effect: .allow),
        PermissionRule(action: "skill", resource: "*", effect: .allow),
        PermissionRule(action: "edit", resource: "*", effect: .ask),
        PermissionRule(action: "bash", resource: "*", effect: .ask),
        PermissionRule(action: "mcp:*", resource: "*", effect: .ask),
    ]

    public static let build = Agent(id: "build")
    public static let plan = Agent(
        id: "plan",
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
        for rule in rules.reversed() {
            if wildcardMatch(rule.action, action), wildcardMatch(rule.resource, resource) {
                return rule.effect
            }
        }
        return .ask
    }

    private func wildcardMatch(_ pattern: String, _ value: String) -> Bool {
        pattern == "*" || pattern == value
    }
}
