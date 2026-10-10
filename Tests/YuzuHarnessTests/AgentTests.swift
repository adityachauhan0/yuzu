import Foundation
import Testing
@testable import YuzuHarness

@Suite(.serialized, .readsMCPHub)
struct AgentTests {
    private func makeWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuzu-agent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeRunner(
        project: URL,
        turns: [AssistantTurn],
        stepCount: Int = 0,
        agentID: String = "build"
    ) throws -> (HarnessStore, SessionRunner, ScriptedTurn, String) {
        let store = try HarnessStore(path: project.appendingPathComponent("session.sqlite").path)
        let sessionID = "session-agent"
        try store.insertSession(
            SessionRecord(
                id: sessionID,
                projectPath: project.path,
                agentID: agentID,
                modelIdentifier: "test",
                epochID: "epoch-1",
                stepCount: stepCount,
                supportsMultipleToolCalls: true,
                status: .idle,
                modelMessageCursor: 0
            )
        )
        let script = ScriptedTurn(turns: turns)
        let runner = SessionRunner(sessionID: sessionID, store: store, model: script)
        return (store, runner, script, sessionID)
    }

    @Test func A1_taskRunsChildOnSameLock() async throws {
        AgentCatalog.resetCustomAgentsForTests()
        defer { AgentCatalog.resetCustomAgentsForTests() }

        let project = try makeWorkspace()
        let taskCall = ToolCall(
            id: "task-1",
            name: "task",
            arguments: .object([
                "agent": .string("plan"),
                "prompt": .string("look"),
            ])
        )
        let turns = [
            AssistantTurn(text: "", toolCalls: [taskCall]),
            AssistantTurn(text: "looked"),
            AssistantTurn(text: "done"),
        ]
        let (store, runner, script, sessionID) = try makeRunner(project: project, turns: turns)
        try "x".write(
            to: project.appendingPathComponent("note.txt"),
            atomically: true,
            encoding: .utf8
        )

        await runner.prompt("go", delivery: .queue)
        await runner.run()

        let tool = try #require(
            try store.messages(sessionID: sessionID).first { $0.role == .tool && $0.toolName == "task" }
        )
        #expect(tool.text.contains("looked"))
        #expect(!ScriptedTurn.intervalsOverlap(script.completeIntervals))
        #expect(script.completeIntervals.count >= 2)
    }

    @Test func A2_planChildCannotEdit() async throws {
        AgentCatalog.resetCustomAgentsForTests()
        defer { AgentCatalog.resetCustomAgentsForTests() }

        let project = try makeWorkspace()
        try "needle".write(
            to: project.appendingPathComponent("child.txt"),
            atomically: true,
            encoding: .utf8
        )
        let taskCall = ToolCall(
            id: "task-1",
            name: "task",
            arguments: .object([
                "agent": .string("plan"),
                "prompt": .string("edit it"),
            ])
        )
        let editCall = ToolCall(
            id: "edit-1",
            name: "edit",
            arguments: .object([
                "path": .string("child.txt"),
                "old_string": .string("needle"),
                "new_string": .string("changed"),
            ])
        )
        let turns = [
            AssistantTurn(text: "", toolCalls: [taskCall]),
            AssistantTurn(text: "", toolCalls: [editCall]),
            AssistantTurn(text: "child finished"),
            AssistantTurn(text: "parent done"),
        ]
        let (store, runner, _, sessionID) = try makeRunner(project: project, turns: turns)

        await runner.prompt("go", delivery: .queue)
        await runner.run()

        let childDenial = try store.toolMessagesContaining(
            text: PermissionGate.denialMessage,
            sessionIDPrefix: "\(sessionID)-sub-"
        )
        #expect(!childDenial.isEmpty)
        let taskResult = try #require(
            try store.messages(sessionID: sessionID).first { $0.role == .tool && $0.toolName == "task" }
        )
        #expect(taskResult.text.contains("child finished"))
        let file = try String(contentsOf: project.appendingPathComponent("child.txt"), encoding: .utf8)
        #expect(file == "needle")
    }

    @Test func A3_parentStepsIgnoreChildTurns() async throws {
        AgentCatalog.resetCustomAgentsForTests()
        defer { AgentCatalog.resetCustomAgentsForTests() }

        AgentCatalog.registerForTests(Agent(id: "parent-stepped", mode: .all, steps: 3))

        let project = try makeWorkspace()
        try "body".write(
            to: project.appendingPathComponent("note.txt"),
            atomically: true,
            encoding: .utf8
        )
        let taskCall = ToolCall(
            id: "task-1",
            name: "task",
            arguments: .object([
                "agent": .string("plan"),
                "prompt": .string("work"),
            ])
        )
        let readCall = ToolCall(
            id: "read-child",
            name: "read",
            arguments: .object(["path": .string("note.txt")])
        )
        let turns = [
            AssistantTurn(text: "", toolCalls: [taskCall]),
            AssistantTurn(text: "", toolCalls: [readCall]),
            AssistantTurn(text: "", toolCalls: [readCall]),
            AssistantTurn(text: "", toolCalls: [readCall]),
            AssistantTurn(text: "", toolCalls: [readCall]),
            AssistantTurn(text: "child done"),
        ]
        let (store, runner, _, sessionID) = try makeRunner(
            project: project,
            turns: turns,
            stepCount: 2,
            agentID: "parent-stepped"
        )

        await runner.prompt("go", delivery: .queue)
        await runner.run()

        let session = try #require(try store.session(id: sessionID))
        #expect(session.stepCount == 3)
    }
}
