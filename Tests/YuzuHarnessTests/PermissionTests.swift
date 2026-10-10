import Foundation
import Testing
@testable import YuzuHarness

struct PermissionTests {
    private func makeWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuzu-perm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func waitUntil(timeout: TimeInterval, condition: () throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        Issue.record("condition not met before timeout")
    }

    @Test func P1_lastMatchWins() {
        let rules = [
            PermissionRule(action: "edit", resource: "*", effect: .ask),
            PermissionRule(action: "edit", resource: "*", effect: .allow),
            PermissionRule(action: "edit", resource: "*", effect: .deny),
        ]
        #expect(PermissionEvaluator.evaluateRules(rules, action: "edit", resource: "*") == .deny)

        let reversed = [
            PermissionRule(action: "edit", resource: "*", effect: .deny),
            PermissionRule(action: "edit", resource: "*", effect: .allow),
        ]
        #expect(PermissionEvaluator.evaluateRules(reversed, action: "edit", resource: "*") == .allow)
    }

    @Test func P2_defaultIsAsk() {
        #expect(PermissionEvaluator.evaluateRules([], action: "edit", resource: "*") == .ask)
    }

    @Test func P3_unknownAgentDeniesAll() {
        #expect(
            PermissionEvaluator.effect(
                agentID: "mystery",
                action: "edit",
                resource: "*",
                savedAllows: [],
                manualPressed: true
            ) == .deny
        )
    }

    @Test func P4_buildAsksForEdit() {
        #expect(
            PermissionEvaluator.effect(
                agentID: "build",
                action: "read",
                resource: "*",
                savedAllows: [],
                manualPressed: true
            ) == .allow
        )
        #expect(
            PermissionEvaluator.effect(
                agentID: "build",
                action: "edit",
                resource: "*",
                savedAllows: [],
                manualPressed: true
            ) == .ask
        )
        #expect(
            PermissionEvaluator.effect(
                agentID: "build",
                action: "bash",
                resource: "*",
                savedAllows: [],
                manualPressed: true
            ) == .ask
        )
    }

    @Test func P5_planDeniesEditAndBash() async throws {
        let savedAllow = [PermissionRule(action: "edit", resource: "*", effect: .allow)]
        #expect(
            PermissionEvaluator.effect(
                agentID: "plan",
                action: "read",
                resource: "*",
                savedAllows: [],
                manualPressed: true
            ) == .allow
        )
        #expect(
            PermissionEvaluator.effect(
                agentID: "plan",
                action: "edit",
                resource: "*",
                savedAllows: savedAllow,
                manualPressed: true
            ) == .deny
        )
        #expect(
            PermissionEvaluator.effect(
                agentID: "plan",
                action: "bash",
                resource: "*",
                savedAllows: [],
                manualPressed: true
            ) == .deny
        )

        let project = try makeWorkspace()
        let store = try HarnessStore(path: project.appendingPathComponent("session.sqlite").path)
        try store.insertPermissionRule(
            projectPath: project.path,
            rule: PermissionRule(action: "edit", resource: "*", effect: .allow)
        )
        let sessionID = "s-plan-p5"
        try store.insertSession(
            SessionRecord(
                id: sessionID,
                projectPath: project.path,
                agentID: "plan",
                modelIdentifier: "test",
                epochID: "epoch-1",
                stepCount: 0,
                supportsMultipleToolCalls: true,
                status: .idle,
                modelMessageCursor: 0
            )
        )
        let editCall = ToolCall(
            id: "c1",
            name: "edit",
            arguments: .object([
                "path": .string("a.swift"),
                "old_string": .string("a"),
                "new_string": .string("b"),
            ])
        )
        let script = ScriptedTurn(turns: [
            AssistantTurn(text: "", toolCalls: [editCall]),
            AssistantTurn(text: "done"),
        ])
        let runner = SessionRunner(sessionID: sessionID, store: store, model: script)
        await runner.prompt("go", delivery: .queue)

        let events = try store.harnessEvents(sessionID: sessionID)
        #expect(!events.contains { $0.name == "permission.asked" })
        #expect(
            try store.messages(sessionID: sessionID).contains {
                $0.role == .tool && $0.text == PermissionGate.denialMessage
            }
        )
    }

    @Test func P6_onceDoesNotSave() async throws {
        let project = try makeWorkspace()
        let dbURL = project.appendingPathComponent("session.sqlite")
        let store = try HarnessStore(path: dbURL.path)
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
        try "a".write(to: project.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)
        let editCall = ToolCall(
            id: "c1",
            name: "edit",
            arguments: .object([
                "path": .string("a.swift"),
                "old_string": .string("a"),
                "new_string": .string("b"),
            ])
        )
        let script = ScriptedTurn(turns: [
            AssistantTurn(text: "", toolCalls: [editCall]),
            AssistantTurn(text: "done"),
        ])
        let runner = SessionRunner(sessionID: sessionID, store: store, model: script)

        let rulesBefore = try store.permissionRules(projectPath: project.path)
        _ = try store.appendInbox(sessionID: sessionID, text: "go", delivery: .queue)
        let runTask = Task { await runner.run() }

        try await waitUntil(timeout: 3) {
            !(try store.pendingPermissionRequests(sessionID: sessionID).isEmpty)
        }
        let pending = try #require(try store.pendingPermissionRequests(sessionID: sessionID).first)
        await runner.replyPermission(pending.id, .once)
        await runTask.value

        let rulesAfter = try store.permissionRules(projectPath: project.path)
        #expect(rulesBefore == rulesAfter)
        #expect(
            try store.messages(sessionID: sessionID).contains {
                $0.role == .tool && $0.text.contains("Edited")
            }
        )
    }

    @Test func P7_alwaysSaves() async throws {
        let project = try makeWorkspace()
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
        let path = "src/a.swift"
        try FileManager.default.createDirectory(at: project.appendingPathComponent("src"), withIntermediateDirectories: true)
        try "a".write(to: project.appendingPathComponent(path), atomically: true, encoding: .utf8)
        let editCall1 = ToolCall(
            id: "c1",
            name: "edit",
            arguments: .object([
                "path": .string(path),
                "old_string": .string("a"),
                "new_string": .string("b"),
            ])
        )
        let editCall2 = ToolCall(
            id: "c2",
            name: "edit",
            arguments: .object([
                "path": .string(path),
                "old_string": .string("b"),
                "new_string": .string("c"),
            ])
        )
        let script = ScriptedTurn(turns: [
            AssistantTurn(text: "", toolCalls: [editCall1]),
            AssistantTurn(text: "", toolCalls: [editCall2]),
            AssistantTurn(text: "done"),
        ])
        let runner = SessionRunner(sessionID: sessionID, store: store, model: script)
        _ = try store.appendInbox(sessionID: sessionID, text: "go", delivery: .queue)
        let runTask = Task { await runner.run() }

        try await waitUntil(timeout: 3) {
            !(try store.pendingPermissionRequests(sessionID: sessionID).isEmpty)
        }
        let pending = try #require(try store.pendingPermissionRequests(sessionID: sessionID).first)
        await runner.replyPermission(pending.id, .always)
        await runTask.value

        let saved = try store.permissionRules(projectPath: project.path)
        #expect(
            saved.contains {
                $0.action == "edit" && $0.resource == path && $0.effect == .allow
            }
        )
        let asked = try store.harnessEvents(sessionID: sessionID).filter { $0.name == "permission.asked" }
        #expect(asked.count == 1)
        let edited = try store.messages(sessionID: sessionID).filter {
            $0.role == .tool && $0.text.contains("Edited \(path)")
        }
        #expect(edited.count == 2)
        #expect(try String(contentsOf: project.appendingPathComponent(path), encoding: .utf8) == "c")
    }

    @Test func P8_rejectContinues() async throws {
        let project = try makeWorkspace()
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
        let editCall = ToolCall(
            id: "c1",
            name: "edit",
            arguments: .object([
                "path": .string("a.swift"),
                "old_string": .string("a"),
                "new_string": .string("b"),
            ])
        )
        let script = ScriptedTurn(turns: [
            AssistantTurn(text: "", toolCalls: [editCall]),
            AssistantTurn(text: "recovered"),
        ])
        let runner = SessionRunner(sessionID: sessionID, store: store, model: script)
        _ = try store.appendInbox(sessionID: sessionID, text: "go", delivery: .queue)
        let runTask = Task { await runner.run() }

        try await waitUntil(timeout: 3) {
            !(try store.pendingPermissionRequests(sessionID: sessionID).isEmpty)
        }
        let pending = try #require(try store.pendingPermissionRequests(sessionID: sessionID).first)
        await runner.replyPermission(pending.id, .reject)
        await runTask.value

        let tool = try #require(
            try store.messages(sessionID: sessionID).first { $0.role == .tool }
        )
        #expect(tool.text.lowercased().contains("denied"))
        #expect(try store.messages(sessionID: sessionID).last?.text == "recovered")
        let session = try #require(try store.session(id: sessionID))
        #expect(session.status == .idle)
    }

    @Test func P9_denySkipsUI() async throws {
        let project = try makeWorkspace()
        let store = try HarnessStore(path: project.appendingPathComponent("session.sqlite").path)
        let sessionID = "s1"
        try store.insertSession(
            SessionRecord(
                id: sessionID,
                projectPath: project.path,
                agentID: "plan",
                modelIdentifier: "test",
                epochID: "epoch-1",
                stepCount: 0,
                supportsMultipleToolCalls: true,
                status: .idle,
                modelMessageCursor: 0
            )
        )
        let editCall = ToolCall(
            id: "c1",
            name: "edit",
            arguments: .object([
                "path": .string("a.swift"),
                "old_string": .string("a"),
                "new_string": .string("b"),
            ])
        )
        let script = ScriptedTurn(turns: [
            AssistantTurn(text: "", toolCalls: [editCall]),
            AssistantTurn(text: "done"),
        ])
        let runner = SessionRunner(sessionID: sessionID, store: store, model: script)
        await runner.prompt("go", delivery: .queue)
        await runner.run()

        let events = try store.harnessEvents(sessionID: sessionID)
        #expect(!events.contains { $0.name == "permission.asked" })
        #expect(
            try store.messages(sessionID: sessionID).contains {
                $0.role == .tool && $0.text.lowercased().contains("denied")
            }
        )
    }

    @Test func P10_manualToggle() async throws {
        #expect(
            PermissionEvaluator.effect(
                agentID: "build",
                action: "edit",
                resource: "*",
                savedAllows: [],
                manualPressed: true
            ) == .ask
        )
        #expect(
            PermissionEvaluator.effect(
                agentID: "build",
                action: "bash",
                resource: "*",
                savedAllows: [],
                manualPressed: true
            ) == .ask
        )
        #expect(
            PermissionEvaluator.effect(
                agentID: "build",
                action: "edit",
                resource: "*",
                savedAllows: [],
                manualPressed: false
            ) == .allow
        )
        #expect(
            PermissionEvaluator.effect(
                agentID: "build",
                action: "bash",
                resource: "*",
                savedAllows: [],
                manualPressed: false
            ) == .ask
        )

        let project = try makeWorkspace()
        let store = try HarnessStore(path: project.appendingPathComponent("session.sqlite").path)
        let sessionID = "s-manual"
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
                manualPressed: false
            )
        )
        try "a".write(to: project.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)
        let editCall = ToolCall(
            id: "c1",
            name: "edit",
            arguments: .object([
                "path": .string("a.swift"),
                "old_string": .string("a"),
                "new_string": .string("b"),
            ])
        )
        let bashCall = ToolCall(
            id: "c2",
            name: "bash",
            arguments: .object(["command": .string("echo hi")])
        )
        let script = ScriptedTurn(turns: [
            AssistantTurn(text: "", toolCalls: [editCall]),
            AssistantTurn(text: "", toolCalls: [bashCall]),
            AssistantTurn(text: "done"),
        ])
        let runner = SessionRunner(sessionID: sessionID, store: store, model: script)
        _ = try store.appendInbox(sessionID: sessionID, text: "go", delivery: .queue)
        let runTask = Task { await runner.run() }

        try await waitUntil(timeout: 3) {
            !(try store.pendingPermissionRequests(sessionID: sessionID).isEmpty)
        }
        let pending = try #require(try store.pendingPermissionRequests(sessionID: sessionID).first)
        #expect(pending.action == "bash")
        await runner.replyPermission(pending.id, .once)
        await runTask.value

        let asked = try store.harnessEvents(sessionID: sessionID).filter { $0.name == "permission.asked" }
        #expect(asked.count == 1)
        #expect(
            try store.messages(sessionID: sessionID).contains {
                $0.role == .tool && $0.text.contains("Edited")
            }
        )
        #expect(
            try store.messages(sessionID: sessionID).contains {
                $0.role == .tool && $0.text.contains("Ran:")
            }
        )
    }
}
