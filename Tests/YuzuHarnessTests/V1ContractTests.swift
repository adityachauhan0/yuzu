import Foundation
import Testing
@testable import YuzuHarness

@Suite(.readsMCPHub)
struct V1ContractTests {
    @Test func toolRowOracle_readSecretTxt() {
        let call = ToolCall(
            id: "read-secret",
            name: "read",
            arguments: .object(["path": .string("secret.txt")])
        )
        let row = V1ToolRowSpec.expectedRow(for: call)
        #expect(row == V1ToolRowSpec.Row(title: "Read", detail: "secret.txt"))
        #expect(V1ToolRowFormatterBridge.format(call) == row)
    }

    @Test func toolRowOracle_writeEditShellGrepGlob() {
        let samples: [(ToolCall, V1ToolRowSpec.Row)] = [
            (
                ToolCall(id: "w", name: "write", arguments: .object(["path": .string("out.txt")])),
                V1ToolRowSpec.Row(title: "Write", detail: "out.txt")
            ),
            (
                ToolCall(id: "e", name: "edit", arguments: .object(["path": .string("main.swift")])),
                V1ToolRowSpec.Row(title: "Edit", detail: "main.swift")
            ),
            (
                ToolCall(id: "b", name: "bash", arguments: .object(["command": .string("ls -la")])),
                V1ToolRowSpec.Row(title: "Shell", detail: "ls -la")
            ),
            (
                ToolCall(id: "g", name: "grep", arguments: .object(["pattern": .string("TODO")])),
                V1ToolRowSpec.Row(title: "Grep", detail: "TODO")
            ),
            (
                ToolCall(id: "gl", name: "glob", arguments: .object(["pattern": .string("**/*.swift")])),
                V1ToolRowSpec.Row(title: "Glob", detail: "**/*.swift")
            ),
        ]
        for (call, expected) in samples {
            #expect(V1ToolRowSpec.expectedRow(for: call) == expected)
            #expect(V1ToolRowFormatterBridge.format(call) == expected)
        }
    }

    @Test func toolRowOracle_skillAndTask() {
        let skill = ToolCall(
            id: "s",
            name: "skill",
            arguments: .object(["name": .string("customize-yuzu")])
        )
        #expect(V1ToolRowSpec.expectedRow(for: skill) == V1ToolRowSpec.Row(title: "Skill", detail: "Loaded customize-yuzu"))

        let task = ToolCall(
            id: "t",
            name: "task",
            arguments: .object([
                "agent": .string("explore"),
                "prompt": .string("Find the parser\nsecond line ignored"),
            ])
        )
        #expect(V1ToolRowSpec.expectedRow(for: task) == V1ToolRowSpec.Row(title: "Task", detail: "Find the parser"))
    }

    @Test func K5_compactionSummaryStoredOnSession() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuzu-v1-compact-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dbURL = root.appendingPathComponent("session.sqlite")
        let store = try HarnessStore(path: dbURL.path)
        let sessionID = "session-v1-k5"
        try store.insertSession(
            SessionRecord(
                id: sessionID,
                projectPath: root.path,
                agentID: "build",
                modelIdentifier: "test",
                epochID: "epoch-1",
                stepCount: 0,
                supportsMultipleToolCalls: true,
                status: .idle,
                modelMessageCursor: 0,
                contextLength: 1_000,
                compactionBufferTokens: 200,
                compactionKeepTokens: 100
            )
        )
        let script = ScriptedTurn(turns: [
            AssistantTurn(text: "## Goal\ncompacted"),
            AssistantTurn(text: "done"),
        ])
        let runner = SessionRunner(sessionID: sessionID, store: store, model: script)
        let padding = String(repeating: "z", count: 900)
        try store.appendMessage(sessionID: sessionID, message: .user("DROPME"), epochID: "epoch-1")
        for index in 0..<4 {
            try store.appendMessage(
                sessionID: sessionID,
                message: .user("bulk-\(index) \(padding)"),
                epochID: "epoch-1"
            )
            try store.appendMessage(
                sessionID: sessionID,
                message: .assistant(AssistantTurn(text: "ack-\(index)")),
                epochID: "epoch-1"
            )
        }
        try store.appendMessage(sessionID: sessionID, message: .user("KEEPME"), epochID: "epoch-1")

        await runner.run()

        let session = try #require(try store.session(id: sessionID))
        #expect(session.epochID != "epoch-1")
        let summary = try #require(session.compactionSummary)
        #expect(summary.contains("Goal"))
    }

    @Test func V1_questionTool_storesAnswer() async {
        let call = ToolCall(
            id: "q1",
            name: QuestionTool.definition.name,
            arguments: .object(["question": .string("Which API key?")])
        )
        let expected = V1ToolRowSpec.Row(title: "Question", detail: "Which API key?")
        #expect(V1ToolRowSpec.expectedRow(for: call) == expected)
        #expect(V1ToolRowFormatterBridge.format(call) == expected)

        let answerTask = Task {
            await QuestionTool.Broker.shared.register(
                sessionID: "session-q",
                callID: call.id,
                question: "Which API key?"
            )
        }
        await QuestionTool.Broker.shared.answer(sessionID: "session-q", callID: call.id, text: "from-env")
        #expect(await answerTask.value == "from-env")
    }

    @Test func V1_revertLastUserTurn_rewindsTranscript() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuzu-v1-revert-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = try HarnessStore(path: root.appendingPathComponent("session.sqlite").path)
        let sessionID = "session-revert"
        try store.insertSession(
            SessionRecord(
                id: sessionID,
                projectPath: root.path,
                agentID: "build",
                modelIdentifier: "test",
                epochID: "epoch-1",
                stepCount: 0,
                supportsMultipleToolCalls: true,
                status: .idle,
                modelMessageCursor: 4
            )
        )
        try store.appendMessage(sessionID: sessionID, message: .user("first"))
        try store.appendMessage(sessionID: sessionID, message: .assistant(AssistantTurn(text: "a1")))
        try store.appendMessage(sessionID: sessionID, message: .user("second"))
        try store.appendMessage(sessionID: sessionID, message: .assistant(AssistantTurn(text: "a2")))

        #expect(try store.revertLastUserTurn(sessionID: sessionID))
        let texts = try store.messages(sessionID: sessionID).map(\.text)
        #expect(texts == ["first", "a1"])
        let session = try #require(try store.session(id: sessionID))
        #expect(session.modelMessageCursor == 2)
    }

    @Test func V1_webfetchTool_truncatesLongText() {
        let longBody = String(repeating: "x", count: ToolOutput.productionCharacterCap + 50)
        let projected = ToolOutput.project(raw: longBody, sessionID: "s", callID: "wf")
        #expect(projected != longBody)
        #expect(projected.contains("truncated"))
        #expect(projected.contains("Full output:"))
    }
}
