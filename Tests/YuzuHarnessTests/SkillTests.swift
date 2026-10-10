import Foundation
import Testing
@testable import YuzuHarness

@Suite(.readsMCPHub)
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
        #expect(epoch.baselineText.contains("- customize-yuzu:"))
        #expect(epoch.baselineText.contains("Yuzu's own configuration"))
        #expect(!epoch.baselineText.contains(SkillCatalog.customizeYuzuUniqueBodyMarker))
        #expect(!epoch.baselineText.contains("## Scope"))
    }

    @Test func missingSkillDoesNotLoop() async throws {
        let project = try makeWorkspace()
        let (store, runner, script, sessionID) = try makeRunner(
            project: project,
            turns: [
                AssistantTurn(
                    text: "",
                    toolCalls: [
                        ToolCall(id: "call-poem", name: "skill", arguments: .object(["name": .string("poem")])),
                    ]
                ),
                AssistantTurn(
                    text: "",
                    toolCalls: [
                        ToolCall(id: "call-poem-2", name: "skill", arguments: .object(["name": .string("poem")])),
                    ]
                ),
                AssistantTurn(text: "should not run"),
            ]
        )

        await runner.prompt("tell me a poem", delivery: .queue)
        await runner.run()

        let messages = try store.messages(sessionID: sessionID)
        let tools = messages.filter { $0.role == StoredMessage.Role.tool }
        #expect(tools.count == 1)
        #expect(tools[0].text.contains("skill not found: poem"))
        #expect(tools[0].text.contains("Available skills:"))
        #expect(tools[0].text.contains("customize-yuzu"))
        #expect(tools[0].text.contains("Do not call the skill tool again"))
        let last = try #require(messages.last)
        #expect(last.role == StoredMessage.Role.assistant)
        #expect(last.toolCalls.isEmpty)
        #expect(!last.text.contains("should not run"))
        #expect(script.requests.count == 2)
        #expect(script.requests[0].tools.contains { $0.name == "skill" })
        #expect(!script.requests[1].tools.contains { $0.name == "skill" })
        let row = ToolRowFormatter.present(
            call: ToolCall(id: "call-poem", name: "skill", arguments: .object(["name": .string("poem")])),
            result: tools[0].text
        )
        #expect(row.detail == "No skill named poem")
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
        #expect(result.contains("<skill_content"))
        #expect(result.contains(SkillCatalog.customizeYuzuUniqueBodyMarker))
        #expect(result.contains("Base directory:"))
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
        #expect(!tools.allowedNames.contains("skill"))
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
        #expect(guidance.contains("- demo: \(description)"))
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

    @Test func slashSkillAdmitsBody() {
        let skill = SkillRecord(
            name: "brief",
            description: "A short brief",
            body: "Write a brief.",
            directoryPath: "/tmp/brief",
            slash: true
        )
        let hidden = SkillRecord(
            name: "hidden",
            description: "Not a command",
            body: "Secret.",
            directoryPath: "/tmp/hidden",
            slash: false
        )
        #expect(ComposerCommands.skillExpansion(text: "/brief extra detail", skills: [skill, hidden]) == "Write a brief.\n\nextra detail")
        #expect(ComposerCommands.skillExpansion(text: "/hidden", skills: [skill, hidden]) == nil)
        #expect(ComposerCommands.skillExpansion(text: "not a command", skills: [skill]) == nil)
    }

    @Test func oauthChallengeKeepsTheAuthorizationURI() {
        let header = "Bearer realm=\"mcp\", authorization_uri=\"http://127.0.0.1/oauth\""
        #expect(OAuthChallenge.authorizationURI(from: header) == "http://127.0.0.1/oauth")
        #expect(OAuthChallenge.parse(header).tokenURI == nil)
        let both = "Bearer authorization_uri=\"http://127.0.0.1/oauth\", token_uri=\"http://127.0.0.1/token\""
        #expect(OAuthChallenge.parse(both).tokenURI == "http://127.0.0.1/token")
        #expect(OAuthChallenge.authorizationURI(from: "Bearer realm=\"mcp\"") == nil)
    }
}
