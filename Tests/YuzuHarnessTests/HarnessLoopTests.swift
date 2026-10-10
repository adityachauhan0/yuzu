import Foundation
import Testing
@testable import YuzuHarness

struct HarnessLoopTests {
    private func makeWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuzu-harness-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeRunner(
        project: URL? = nil,
        turns: [AssistantTurn],
        supportsMultiple: Bool = true,
        stepCount: Int = 0
    ) throws -> (HarnessStore, SessionRunner, ScriptedTurn, String, URL) {
        let projectDir: URL
        if let project {
            projectDir = project
        } else {
            projectDir = try makeWorkspace()
        }
        let dbURL = projectDir.appendingPathComponent("session.sqlite")
        let store = try HarnessStore(path: dbURL.path)
        let sessionID = "session-1"
        let session = SessionRecord(
            id: sessionID,
            projectPath: projectDir.path,
            agentID: "build",
            modelIdentifier: "test",
            epochID: "epoch-1",
            stepCount: stepCount,
            supportsMultipleToolCalls: supportsMultiple,
            status: .idle,
            modelMessageCursor: 0
        )
        try store.insertSession(session)
        let script = ScriptedTurn(turns: turns)
        let runner = SessionRunner(sessionID: sessionID, store: store, model: script)
        return (store, runner, script, sessionID, projectDir)
    }

    private func waitUntil(timeout: TimeInterval, condition: () throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        Issue.record("condition not met before timeout")
    }

    @Test func L1_promptStaysInInboxUntilPromotion() async throws {
        let (store, runner, _, sessionID, _) = try makeRunner(turns: [AssistantTurn(text: "done")])
        _ = try store.appendInbox(sessionID: sessionID, text: "hi", delivery: .queue)
        runner.holdBeforeQueuePromotion = true
        defer { runner.releaseQueuePromotionHold() }

        let runTask = Task { await runner.run() }
        try await waitUntil(timeout: 2) {
            try store.userMessages(sessionID: sessionID).isEmpty
                && !(try store.inboxRows(sessionID: sessionID).isEmpty)
        }

        let inbox = try store.inboxRows(sessionID: sessionID)
        #expect(inbox.count == 1)
        #expect(inbox[0].text == "hi")
        #expect(try store.userMessages(sessionID: sessionID).count == 0)

        runTask.cancel()
    }

    @Test func L2_textOnlyTurnCompletes() async throws {
        let (store, runner, _, sessionID, _) = try makeRunner(turns: [AssistantTurn(text: "done")])
        await runner.prompt("hi", delivery: .queue)
        await runner.run()

        let session = try #require(try store.session(id: sessionID))
        #expect(session.status == SessionStatus.idle)
        let messages = try store.messages(sessionID: sessionID)
        #expect(messages.filter { $0.role == StoredMessage.Role.user }.count == 1)
        #expect(messages.last?.role == StoredMessage.Role.assistant)
        #expect(messages.last?.text == "done")
    }

    @Test func L3_toolRoundTrip() async throws {
        let project = try makeWorkspace()
        try "hello".write(to: project.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)

        let readCall = ToolCall(
            id: "call-1",
            name: "read",
            arguments: .object(["path": .string("note.txt")])
        )
        let (store, runner, script, sessionID, _) = try makeRunner(
            project: project,
            turns: [
                AssistantTurn(text: "", toolCalls: [readCall]),
                AssistantTurn(text: "saw it"),
            ]
        )

        await runner.prompt("go", delivery: .queue)
        await runner.run()

        #expect(script.requests.count == 2)
        #expect(script.requests[0].toolTurnLimit == 0)
        #expect(script.requests[0].delta.contains { $0.role == StoredMessage.Role.user })
        #expect(script.requests[1].delta.count == 1)
        #expect(script.requests[1].delta[0].role == StoredMessage.Role.tool)
        #expect(!script.requests[1].delta.contains { $0.role == StoredMessage.Role.user })
        #expect(try store.messages(sessionID: sessionID).contains { $0.role == StoredMessage.Role.tool && $0.text.contains("hello") })
        #expect(try store.messages(sessionID: sessionID).last?.text == "saw it")
    }

    @Test func L4_unknownToolIsAResult() async throws {
        let call = ToolCall(id: "c1", name: "nope", arguments: .object([:]))
        let (store, runner, _, sessionID, _) = try makeRunner(turns: [AssistantTurn(text: "", toolCalls: [call])])
        await runner.prompt("go", delivery: .queue)
        await runner.run()

        let session = try #require(try store.session(id: sessionID))
        #expect(session.status == SessionStatus.idle)
        #expect(try store.messages(sessionID: sessionID).contains { $0.role == StoredMessage.Role.tool && $0.text.contains("Unknown tool") })
    }

    @Test func L5_staleTool() async throws {
        let call = ToolCall(id: "c1", name: "read", arguments: .object(["path": .string("note.txt")]))
        let (store, runner, _, sessionID, _) = try makeRunner(turns: [AssistantTurn(text: "", toolCalls: [call])])
        runner.materializeOnly = ["glob", "grep"]
        await runner.prompt("go", delivery: .queue)
        await runner.run()

        #expect(try store.messages(sessionID: sessionID).contains { $0.role == StoredMessage.Role.tool && $0.text.contains("Stale tool call") })
    }

    @Test func L6_singleCallWhenUnsupported() async throws {
        let calls = [
            ToolCall(id: "c1", name: "read", arguments: .object(["path": .string("a.txt")])),
            ToolCall(id: "c2", name: "read", arguments: .object(["path": .string("b.txt")])),
        ]
        let project = try makeWorkspace()
        try "a".write(to: project.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let (store, runner, _, sessionID, _) = try makeRunner(
            project: project,
            turns: [AssistantTurn(text: "", toolCalls: calls), AssistantTurn(text: "ok")],
            supportsMultiple: false
        )
        await runner.prompt("go", delivery: .queue)
        await runner.run()

        let assistant = try store.messages(sessionID: sessionID).last(where: { $0.role == StoredMessage.Role.assistant && !$0.toolCalls.isEmpty })
        #expect(assistant?.toolCalls.count == 1)
        #expect(assistant?.toolCalls.first?.id == "c1")
        #expect(try store.messages(sessionID: sessionID).filter { $0.role == StoredMessage.Role.tool }.count == 1)
    }

    @Test func L7_cancelDropsBareToolCall() async throws {
        let call = ToolCall(id: "c1", name: "read", arguments: .object(["path": .string("x.txt")]))
        let (store, runner, script, sessionID, _) = try makeRunner(turns: [AssistantTurn(text: "", toolCalls: [call])])
        runner.holdBeforeToolSettle = true

        _ = try store.appendInbox(sessionID: sessionID, text: "go", delivery: .queue)
        let runTask = Task { await runner.run() }

        try await waitUntil(timeout: 2) {
            let messages = try store.messages(sessionID: sessionID)
            return messages.contains { $0.role == StoredMessage.Role.assistant && !$0.toolCalls.isEmpty }
        }

        let inboxBefore = try store.inboxRows(sessionID: sessionID)
        await runner.cancel()
        #expect(script.resetEpochs.count == 1)
        #expect(script.requests.count == 1)
        runner.releaseToolSettleHold()
        await runTask.value
        if script.requests.count == 1 {
            await runner.run()
        }

        #expect(!(try store.messages(sessionID: sessionID).contains { $0.role == StoredMessage.Role.assistant && !$0.toolCalls.isEmpty }))
        #expect(try store.inboxRows(sessionID: sessionID) == inboxBefore)
        #expect(script.requests.count == 2)
        #expect(script.resetEpochs.count == 1)
    }

    @Test func L8_resumeSettlesDanglingCall() async throws {
        let project = try makeWorkspace()
        try "inside".write(to: project.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)
        let store = try HarnessStore(path: project.appendingPathComponent("session.sqlite").path)
        let sessionID = "s1"
        try store.insertSession(
            SessionRecord(
                id: sessionID,
                projectPath: project.path,
                agentID: "build",
                modelIdentifier: "test",
                epochID: "epoch-1",
                stepCount: 0,
                supportsMultipleToolCalls: true,
                status: .idle,
                modelMessageCursor: 0
            )
        )
        let call = ToolCall(id: "c1", name: "read", arguments: .object(["path": .string("note.txt")]))
        try store.insertAssistantWithDanglingCall(sessionID: sessionID, call: call)

        let script = ScriptedTurn(turns: [AssistantTurn(text: "done")])
        let runner = SessionRunner(sessionID: sessionID, store: store, model: script)
        await runner.run()

        #expect(try store.messages(sessionID: sessionID).contains { $0.role == StoredMessage.Role.tool && $0.text.contains("inside") })
        #expect(script.requests.count == 1)
    }

    @Test func L9_steerResetsStepOnce() async throws {
        let call = ToolCall(id: "c1", name: "read", arguments: .object(["path": .string("note.txt")]))
        let project = try makeWorkspace()
        try "x".write(to: project.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)
        let store = try HarnessStore(path: project.appendingPathComponent("session.sqlite").path)
        let sessionID = "s1"
        try store.insertSession(
            SessionRecord(
                id: sessionID,
                projectPath: project.path,
                agentID: "build",
                modelIdentifier: "test",
                epochID: "epoch-1",
                stepCount: 2,
                supportsMultipleToolCalls: true,
                status: .idle,
                modelMessageCursor: 0
            )
        )
        let script = ScriptedTurn(turns: [AssistantTurn(text: "", toolCalls: [call])])
        let runner = SessionRunner(sessionID: sessionID, store: store, model: script)
        runner.holdBeforeToolSettle = true

        try store.appendMessage(sessionID: sessionID, message: .user("first"))
        let runTask = Task { await runner.run() }

        try await waitUntil(timeout: 2) {
            let messages = try store.messages(sessionID: sessionID)
            return messages.contains { $0.role == StoredMessage.Role.assistant && !$0.toolCalls.isEmpty }
        }

        let sessionAfterToolCall = try #require(try store.session(id: sessionID))
        #expect(sessionAfterToolCall.stepCount == 3)

        try runner.admitSteerDuringSettle("steer")
        runner.holdBeforeProviderTurn = true
        runner.releaseToolSettleHold()

        try await waitUntil(timeout: 2) {
            let session = try store.session(id: sessionID)
            let steered = try store.messages(sessionID: sessionID)
                .contains { $0.role == StoredMessage.Role.user && $0.text == "steer" }
            return session?.stepCount == 1 && steered
        }

        let session = try #require(try store.session(id: sessionID))
        #expect(session.stepCount == 1)
        #expect(try store.messages(sessionID: sessionID).contains { $0.role == StoredMessage.Role.user && $0.text == "steer" })

        runner.releaseProviderTurnHold()
        runTask.cancel()
    }

    @Test func L10_queueWaitsUntilIdle() async throws {
        let call = ToolCall(id: "c1", name: "read", arguments: .object(["path": .string("note.txt")]))
        let project = try makeWorkspace()
        try "hi".write(to: project.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)
        let (store, runner, script, sessionID, _) = try makeRunner(
            project: project,
            turns: [
                AssistantTurn(text: "first", toolCalls: [call]),
                AssistantTurn(text: "second reply"),
            ]
        )
        runner.holdBeforeToolSettle = true

        _ = try store.appendInbox(sessionID: sessionID, text: "one", delivery: .queue)
        let runTask = Task { await runner.run() }

        try await waitUntil(timeout: 3) {
            let messages = try store.messages(sessionID: sessionID)
            return messages.contains { $0.role == StoredMessage.Role.assistant && !$0.toolCalls.isEmpty }
        }

        let usersMid = try store.userMessages(sessionID: sessionID)
        #expect(usersMid.count == 1)
        #expect(usersMid[0].text == "one")
        #expect(script.requests.count == 1)
        #expect(!script.requests[0].delta.contains { $0.role == StoredMessage.Role.user && $0.text == "two" })

        _ = try store.appendInbox(sessionID: sessionID, text: "two", delivery: .queue)
        let inboxWhilePending = try store.inboxRows(sessionID: sessionID)
        #expect(inboxWhilePending.contains { $0.text == "two" })
        #expect(try store.userMessages(sessionID: sessionID).count == 1)

        runner.releaseToolSettleHold()
        await runTask.value
        #expect(script.requests.count >= 2)
        #expect(!script.requests[1].delta.contains { $0.role == StoredMessage.Role.user && $0.text == "two" })
        if !(try store.inboxRows(sessionID: sessionID).isEmpty) {
            await runner.run()
        }
        let users = try store.userMessages(sessionID: sessionID)
        #expect(users.count == 2)
        if users.count == 2 {
            #expect(users[1].text == "two")
        }
    }

    @Test func T1_readRejectsEscape() async throws {
        let project = try makeWorkspace()
        let outside = project.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString).txt")
        try "secret".write(to: outside, atomically: true, encoding: .utf8)

        let relativeOutside = "../\(outside.lastPathComponent)"
        let call = ToolCall(id: "c1", name: "read", arguments: .object(["path": .string(relativeOutside)]))
        let (store, runner, _, sessionID, _) = try makeRunner(
            project: project,
            turns: [AssistantTurn(text: "", toolCalls: [call]), AssistantTurn(text: "ok")]
        )
        await runner.prompt("go", delivery: .queue)
        await runner.run()

        let tool = try store.messages(sessionID: sessionID).first { $0.role == StoredMessage.Role.tool }
        #expect(tool != nil)
        #expect(tool?.text.lowercased().contains("error") == true)
        #expect(tool?.text.contains("secret") == false)
    }

    @Test func T2_globAndGrepStayInsideProject() async throws {
        let project = try makeWorkspace()
        try "needle".write(to: project.appendingPathComponent("inside.txt"), atomically: true, encoding: .utf8)
        let outside = project.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString).txt")
        try "needle".write(to: outside, atomically: true, encoding: .utf8)

        let globCall = ToolCall(id: "g1", name: "glob", arguments: .object(["pattern": .string("**/*")]))
        let grepCall = ToolCall(id: "g2", name: "grep", arguments: .object(["pattern": .string("needle")]))
        let (store, runner, _, sessionID, _) = try makeRunner(
            project: project,
            turns: [
                AssistantTurn(text: "", toolCalls: [globCall]),
                AssistantTurn(text: "", toolCalls: [grepCall]),
                AssistantTurn(text: "done"),
            ]
        )
        await runner.prompt("go", delivery: .queue)
        await runner.run()

        let toolTexts = try store.messages(sessionID: sessionID).filter { $0.role == StoredMessage.Role.tool }.map(\.text).joined(separator: "\n")
        #expect(toolTexts.contains("inside.txt"))
        #expect(!toolTexts.contains(outside.lastPathComponent))
    }
}
