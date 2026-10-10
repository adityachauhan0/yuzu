import Foundation
import Testing
@testable import YuzuHarness

struct SkillTests {
    private func makeWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuzu-skills-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeRunner(
        project: URL,
        turns: [AssistantTurn],
        agentID: String = "build"
    ) throws -> (HarnessStore, SessionRunner, ScriptedTurn, String) {
        let dbURL = project.appendingPathComponent("session.sqlite")
        let store = try HarnessStore(path: dbURL.path)
        let sessionID = "session-skills"
        try store.insertSession(
            SessionRecord(
                id: sessionID,
                projectPath: project.path,
                agentID: agentID,
                modelIdentifier: "test",
                epochID: "epoch-1",
                stepCount: 0,
                supportsMultipleToolCalls: true,
                status: .idle,
                modelMessageCursor: 0
            )
        )
        let script = ScriptedTurn(turns: turns)
        let runner = SessionRunner(sessionID: sessionID, store: store, model: script)
        return (store, runner, script, sessionID)
    }

    private func materialize(project: URL, agent: Agent = .build) -> MaterializedTools {
        ToolRegistry.materialize(
            agent: agent,
            projectPath: project.path,
            sessionID: "session-skills",
            savedAllows: [],
            manualPressed: true
        )
    }

    @Test func S1_guidanceListsNameNotBody() async throws {
        let project = try makeWorkspace()
        try "project rules".write(
            to: project.appendingPathComponent("YUZU.md"),
            atomically: true,
            encoding: .utf8
        )

        let (store, runner, _, sessionID) = try makeRunner(
            project: project,
            turns: [AssistantTurn(text: "ok")]
        )

        await runner.prompt("go", delivery: .queue)
        await runner.run()

        let epoch = try #require(try store.epochRecord(sessionID: sessionID, epochID: "epoch-1"))
        #expect(epoch.baselineText.contains("customize-yuzu"))
        #expect(epoch.baselineText.contains("Yuzu's own configuration"))
        #expect(!epoch.baselineText.contains(SkillCatalog.customizeYuzuUniqueBodyMarker))
    }

    @Test func S2_skillToolReturnsBody() throws {
        let project = try makeWorkspace()
        let tools = materialize(project: project)
        let call = ToolCall(
            id: "call-s2",
            name: "skill",
            arguments: .object(["name": .string("customize-yuzu")])
        )
        let result = tools.executeAfterApproval(call: call)
        #expect(result.contains(SkillCatalog.customizeYuzuUniqueBodyMarker))
        let skill = try #require(SkillCatalog.discover(projectPath: project.path).first { $0.name == "customize-yuzu" })
        #expect(result.contains(skill.directoryPath))
    }

    @Test func S3_deniedSkillOmitted() throws {
        let project = try makeWorkspace()
        let agent = Agent(
            id: "skills-deny-one",
            rules: [
                PermissionRule(action: "skill", resource: "*", effect: .allow),
                PermissionRule(action: "skill", resource: "customize-yuzu", effect: .deny),
            ]
        )

        let guidance = SkillCatalog.renderGuidance(rules: agent.rules, projectPath: project.path)
        #expect(!guidance.contains("customize-yuzu"))

        let tools = materialize(project: project, agent: agent)
        #expect(!tools.definitions.contains { $0.name == "skill" })
    }

    @Test func S4_createSkillWritesProjectFile() throws {
        let project = try makeWorkspace()
        let description = "Demo skill for tests"
        let file = try SkillCatalog.createProjectSkill(
            projectPath: project.path,
            name: "demo",
            description: description
        )

        #expect(file.path.hasSuffix("/.yuzu/skills/demo/SKILL.md"))
        let contents = try String(contentsOf: file, encoding: .utf8)
        #expect(contents.contains("name: demo"))
        #expect(contents.contains("description: \(description)"))

        let guidance = SkillCatalog.renderGuidance(agentID: "build", projectPath: project.path)
        #expect(guidance.contains("demo"))
    }

    @Test func S5_duplicateNameProjectWins() throws {
        let project = try makeWorkspace()
        let projectBody = "PROJECT_SKILL_BODY_WINS_SLICE6"
        let directory = SkillCatalog.projectSkillsRoot(projectPath: project.path)
            .appendingPathComponent("customize-yuzu", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        ---
        name: customize-yuzu
        description: Project override
        ---

        \(projectBody)
        """.write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let tools = materialize(project: project)
        let result = tools.executeAfterApproval(
            call: ToolCall(
                id: "call-s5",
                name: "skill",
                arguments: .object(["name": .string("customize-yuzu")])
            )
        )
        #expect(result.contains(projectBody))
        #expect(!result.contains(SkillCatalog.customizeYuzuUniqueBodyMarker))
    }
}
