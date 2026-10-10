import Foundation

public struct MaterializedTools: Sendable {
    public var definitions: [ToolDefinition]
    public var allowedNames: Set<String>
    public let projectPath: String
    public let sessionID: String
    public let agentID: String
    public let savedAllows: [PermissionRule]
    public let manualPressed: Bool

    private static let registeredBuiltinNames: Set<String> = [
        "read", "glob", "grep", "write", "edit", "bash", "skill",
    ]

    private func deliver(call: ToolCall) -> String {
        let raw = BuiltinTools.execute(name: call.name, arguments: call.arguments, projectPath: projectPath)
        return ToolOutput.project(raw: raw, sessionID: sessionID, callID: call.id)
    }

    public func settle(call: ToolCall) -> String {
        if let action = PermissionGate.permissionAction(for: call.name) {
            let resources = PermissionGate.resources(toolName: call.name, arguments: call.arguments)
            let effects = resources.map { resource in
                PermissionEvaluator.effect(
                    agentID: agentID,
                    action: action,
                    resource: resource,
                    savedAllows: savedAllows,
                    manualPressed: manualPressed
                )
            }
            if effects.contains(.deny) {
                return PermissionGate.denialMessage
            }
            if effects.contains(.ask) {
                return "Permission required"
            }
        }

        guard allowedNames.contains(call.name) else {
            if Self.registeredBuiltinNames.contains(call.name)
                || MCPHub.shared.isStaleHarnessName(call.name) {
                return "Stale tool call"
            }
            return "Unknown tool"
        }
        if MCPHub.shared.permissionAction(forHarnessName: call.name) != nil {
            return "MCP tool requires async execution"
        }
        return deliver(call: call)
    }

    public func executeAfterApproval(call: ToolCall) -> String {
        if MCPHub.shared.permissionAction(forHarnessName: call.name) != nil {
            return "MCP tool requires async execution"
        }
        return deliver(call: call)
    }

    public func isMCPTool(_ name: String) -> Bool {
        MCPHub.shared.permissionAction(forHarnessName: name) != nil
    }
}

public enum ToolRegistry {
    private static func shouldMaterializeSkill(agent: Agent, projectPath: String) -> Bool {
        if PermissionEvaluator.evaluateRules(agent.rules, action: "skill", resource: "*") == .deny {
            return false
        }
        return !SkillCatalog.allowedSkills(rules: agent.rules, projectPath: projectPath).isEmpty
    }

    private static let gatedBuiltins: [(ToolDefinition, String)] = [
        (BuiltinTools.read, "read"),
        (BuiltinTools.glob, "glob"),
        (BuiltinTools.grep, "grep"),
        (BuiltinTools.write, "edit"),
        (BuiltinTools.edit, "edit"),
        (BuiltinTools.bash, "bash"),
    ]

    public static func materialize(
        agent: Agent,
        projectPath: String,
        sessionID: String,
        savedAllows: [PermissionRule],
        manualPressed: Bool,
        onlyNames: Set<String>? = nil
    ) -> MaterializedTools {
        var definitions: [ToolDefinition] = []
        var allowed = Set<String>()
        for (tool, action) in gatedBuiltins {
            if onlyNames != nil, !(onlyNames?.contains(tool.name) ?? false) {
                continue
            }
            if PermissionGate.isWhollyDenied(agentID: agent.id, action: action) {
                continue
            }
            definitions.append(tool)
            allowed.insert(tool.name)
        }
        if onlyNames == nil || onlyNames?.contains(BuiltinTools.skill.name) == true {
            if shouldMaterializeSkill(agent: agent, projectPath: projectPath) {
                definitions.append(BuiltinTools.skill)
                allowed.insert(BuiltinTools.skill.name)
            }
        }
        for mcpTool in MCPHub.shared.toolsForMaterialize(agentID: agent.id) {
            if onlyNames != nil, !(onlyNames?.contains(mcpTool.harnessName) ?? false) {
                continue
            }
            definitions.append(mcpTool.definition)
            allowed.insert(mcpTool.harnessName)
        }
        return MaterializedTools(
            definitions: definitions,
            allowedNames: allowed,
            projectPath: projectPath,
            sessionID: sessionID,
            agentID: agent.id,
            savedAllows: savedAllows,
            manualPressed: manualPressed
        )
    }
}
