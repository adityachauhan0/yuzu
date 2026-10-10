import Foundation
import Testing
@testable import YuzuHarness

struct ToolTests {
    private func makeWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuzu-tools-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func materialize(project: URL, sessionID: String = "session-tools") -> MaterializedTools {
        ToolRegistry.materialize(
            agent: .build,
            projectPath: project.path,
            sessionID: sessionID,
            savedAllows: [],
            manualPressed: false
        )
    }

    private func makeRunner(
        project: URL,
        turns: [AssistantTurn],
        manualPressed: Bool = false
    ) throws -> (HarnessStore, SessionRunner, String) {
        let store = try HarnessStore(path: project.appendingPathComponent("session.sqlite").path)
        let sessionID = "session-1"
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
                modelMessageCursor: 0,
                manualPressed: manualPressed
            )
        )
        let script = ScriptedTurn(turns: turns)
        let runner = SessionRunner(sessionID: sessionID, store: store, model: script)
        return (store, runner, sessionID)
    }

    private func waitUntil(timeout: TimeInterval, condition: () throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        Issue.record("condition not met before timeout")
    }

    @Test func T3_editRequiresOneMatch() throws {
        let project = try makeWorkspace()
        let file = project.appendingPathComponent("dup.txt")
        try "needle needle".write(to: file, atomically: true, encoding: .utf8)

        let tools = materialize(project: project)
        let call = ToolCall(
            id: "call-t3",
            name: "edit",
            arguments: .object([
                "path": .string("dup.txt"),
                "old_string": .string("needle"),
                "new_string": .string("pin"),
            ])
        )
        let result = tools.executeAfterApproval(call: call)
        #expect(result.contains("Error"))
        #expect(result.contains("appears 2 times"))
        #expect(try String(contentsOf: file, encoding: .utf8) == "needle needle")
    }

    @Test func T4_editReplacesOne() throws {
        let project = try makeWorkspace()
        let file = project.appendingPathComponent("one.txt")
        try "before needle after".write(to: file, atomically: true, encoding: .utf8)

        let tools = materialize(project: project)
        let call = ToolCall(
            id: "call-t4",
            name: "edit",
            arguments: .object([
                "path": .string("one.txt"),
                "old_string": .string("needle"),
                "new_string": .string("pin"),
            ])
        )
        let result = tools.executeAfterApproval(call: call)
        #expect(result.contains("Edited"))
        #expect(result.contains("pin"))
        #expect(try String(contentsOf: file, encoding: .utf8) == "before pin after")
    }

    @Test func T5_writeCreatesFile() throws {
        let project = try makeWorkspace()
        let tools = materialize(project: project)
        let call = ToolCall(
            id: "call-t5",
            name: "write",
            arguments: .object([
                "path": .string("nested/out.txt"),
                "body": .string("hello write"),
            ])
        )
        let result = tools.executeAfterApproval(call: call)
        #expect(result.contains("Wrote"))
        let written = project.appendingPathComponent("nested/out.txt")
        #expect(FileManager.default.fileExists(atPath: written.path))
        #expect(try String(contentsOf: written, encoding: .utf8) == "hello write")
    }

    @Test func T6_bashCwdIsProject() throws {
        let project = try makeWorkspace()
        let tools = materialize(project: project)
        let call = ToolCall(
            id: "call-t6",
            name: "bash",
            arguments: .object(["command": .string("pwd")])
        )
        let result = tools.executeAfterApproval(call: call)
        let expected = ProjectPaths.projectRootURL(path: project.path).path
        let processCWD = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL.path
        #expect(result.contains(expected))
        if processCWD != expected {
            #expect(!result.contains(processCWD))
        }
    }

    @Test func T7_bashTimesOut() async throws {
        let project = try makeWorkspace()
        let bashCall = ToolCall(
            id: "call-t7",
            name: "bash",
            arguments: .object([
                "command": .string("sleep 30"),
                "timeout": .number(1),
            ])
        )
        let (store, runner, sessionID) = try makeRunner(
            project: project,
            turns: [
                AssistantTurn(text: "", toolCalls: [bashCall]),
                AssistantTurn(text: "still alive"),
            ],
            manualPressed: true
        )
        _ = try store.appendInbox(sessionID: sessionID, text: "go", delivery: .queue)
        let runTask = Task { await runner.run() }

        try await waitUntil(timeout: 5) {
            !(try store.pendingPermissionRequests(sessionID: sessionID).isEmpty)
        }
        let pending = try #require(try store.pendingPermissionRequests(sessionID: sessionID).first)
        await runner.replyPermission(pending.id, .once)
        await runTask.value

        let tool = try #require(try store.messages(sessionID: sessionID).first { $0.role == .tool })
        #expect(tool.text.contains("timed out"))
        #expect(try store.messages(sessionID: sessionID).last?.text == "still alive")
        let session = try #require(try store.session(id: sessionID))
        #expect(session.status == .idle)
    }

    @Test func T8_outputCapWritesFile() throws {
        let previousCap = ToolOutput.characterCapForTesting
        ToolOutput.characterCapForTesting = 100
        defer { ToolOutput.characterCapForTesting = previousCap }

        let project = try makeWorkspace()
        let sessionID = "session-cap"
        let callID = "call-t8"
        let big = String(repeating: "x", count: 10_000)
        let file = project.appendingPathComponent("big.txt")
        try big.write(to: file, atomically: true, encoding: .utf8)

        let tools = materialize(project: project, sessionID: sessionID)
        let call = ToolCall(
            id: callID,
            name: "read",
            arguments: .object(["path": .string("big.txt")])
        )
        let visible = tools.executeAfterApproval(call: call)
        #expect(visible.count < big.count)
        #expect(visible.contains("truncated"))

        let spill = ToolOutput.spillDirectory(sessionID: sessionID, callID: callID)
        #expect(FileManager.default.fileExists(atPath: spill.path))
        #expect(visible.contains(spill.path))
        #expect(try String(contentsOf: spill, encoding: .utf8) == big)
    }
}
