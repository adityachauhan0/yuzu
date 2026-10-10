import Foundation
import Testing
@testable import YuzuHarness

@Suite(.readsMCPHub)
struct ContextTests {
    private func makeWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuzu-context-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeRunner(
        project: URL,
        turns: [AssistantTurn],
        coordinator: ContextCoordinator = ContextCoordinator()
    ) throws -> (HarnessStore, SessionRunner, ScriptedTurn, String) {
        let dbURL = project.appendingPathComponent("session.sqlite")
        let store = try HarnessStore(path: dbURL.path)
        let sessionID = "session-1"
        let session = SessionRecord(
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
        try store.insertSession(session)
        let script = ScriptedTurn(turns: turns)
        let runner = SessionRunner(sessionID: sessionID, store: store, model: script)
        runner.contextCoordinator = coordinator
        return (store, runner, script, sessionID)
    }

    private func systemText(in request: TurnRequest) -> String? {
        request.delta.first { $0.role == .system }?.text
    }

    @Test func C1_baselineFrozen() async throws {
        let project = try makeWorkspace()
        try "baseline-alpha".write(
            to: project.appendingPathComponent("YUZU.md"),
            atomically: true,
            encoding: .utf8
        )

        let (store, runner, script, sessionID) = try makeRunner(
            project: project,
            turns: [AssistantTurn(text: "one"), AssistantTurn(text: "two")]
        )

        await runner.prompt("first", delivery: .queue)
        await runner.run()
        await runner.prompt("second", delivery: .queue)
        await runner.run()

        let epoch = try #require(try store.epochRecord(sessionID: sessionID, epochID: "epoch-1"))
        #expect(epoch.baselineText.contains("baseline-alpha"))

        #expect(script.requests.count == 2)
        let firstSystem = try #require(systemText(in: script.requests[0]))
        let secondSystem = try #require(systemText(in: script.requests[1]))
        #expect(secondSystem == firstSystem)
        #expect(secondSystem == epoch.baselineText)
    }

    @Test func C2_yuzuMdBeatsAgentsMd() async throws {
        let project = try makeWorkspace()
        try "from-yuzu-body".write(
            to: project.appendingPathComponent("YUZU.md"),
            atomically: true,
            encoding: .utf8
        )
        try "from-agents-body".write(
            to: project.appendingPathComponent("AGENTS.md"),
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
        #expect(epoch.baselineText.contains("from-yuzu-body"))
        #expect(!epoch.baselineText.contains("from-agents-body"))
    }

    @Test func C3_agentsMdWhenYuzuMissing() async throws {
        let project = try makeWorkspace()
        try "agents-only-body".write(
            to: project.appendingPathComponent("AGENTS.md"),
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
        #expect(epoch.baselineText.contains("agents-only-body"))
    }

    @Test func C4_changeBecomesOneSystemMessage() async throws {
        let project = try makeWorkspace()
        let yuzuURL = project.appendingPathComponent("YUZU.md")
        try "instructions-v1".write(to: yuzuURL, atomically: true, encoding: .utf8)

        let (store, runner, _, sessionID) = try makeRunner(
            project: project,
            turns: [AssistantTurn(text: "one"), AssistantTurn(text: "two")]
        )

        await runner.prompt("first", delivery: .queue)
        await runner.run()

        let epochBefore = try #require(try store.epochRecord(sessionID: sessionID, epochID: "epoch-1"))
        try "instructions-v2".write(to: yuzuURL, atomically: true, encoding: .utf8)

        await runner.prompt("second", delivery: .queue)
        await runner.run()

        let epochAfter = try #require(try store.epochRecord(sessionID: sessionID, epochID: "epoch-1"))
        #expect(epochAfter.baselineText == epochBefore.baselineText)
        #expect(epochAfter.baselineText.contains("instructions-v1"))
        #expect(!epochAfter.baselineText.contains("instructions-v2"))

        let systemMessages = try store.messages(sessionID: sessionID).filter { $0.role == .system }
        #expect(systemMessages.count == 1)
        #expect(systemMessages[0].text.contains("instructions-v2"))

        let snapshotsData = epochAfter.snapshotsJSON.data(using: .utf8)!
        let snapshots = try JSONDecoder().decode([String: String].self, from: snapshotsData)
        #expect(snapshots[ContextSourceKey.instructions.rawValue]?.contains("instructions-v2") == true)
    }

    @Test func C5_unavailableSourceDoesNotClobber() async throws {
        let project = try makeWorkspace()
        try "stable-instructions".write(
            to: project.appendingPathComponent("YUZU.md"),
            atomically: true,
            encoding: .utf8
        )

        final class FailGate: @unchecked Sendable {
            var shouldFail = false
        }
        let gate = FailGate()
        let coordinator = ContextCoordinator(
            loadInstructions: { path in
                if gate.shouldFail {
                    throw NSError(domain: "test", code: 1)
                }
                return try ContextCoordinator.defaultLoadInstructions(projectPath: path)
            }
        )

        let (store, runner, _, sessionID) = try makeRunner(
            project: project,
            turns: [AssistantTurn(text: "one"), AssistantTurn(text: "two")],
            coordinator: coordinator
        )

        await runner.prompt("first", delivery: .queue)
        await runner.run()

        let epochBefore = try #require(try store.epochRecord(sessionID: sessionID, epochID: "epoch-1"))
        let systemCountBefore = try store.messages(sessionID: sessionID).filter { $0.role == .system }.count

        gate.shouldFail = true
        await runner.prompt("second", delivery: .queue)
        await runner.run()

        let epochAfter = try #require(try store.epochRecord(sessionID: sessionID, epochID: "epoch-1"))
        #expect(epochAfter.baselineText == epochBefore.baselineText)
        #expect(epochAfter.snapshotsJSON == epochBefore.snapshotsJSON)
        let systemCountAfter = try store.messages(sessionID: sessionID).filter { $0.role == .system }.count
        #expect(systemCountAfter == systemCountBefore)
    }

    @Test func C6_firstTurnBlocksWhenBaselineUnavailable() async throws {
        let project = try makeWorkspace()
        let coordinator = ContextCoordinator(
            loadInstructions: { _ in
                throw NSError(domain: "test", code: 1)
            }
        )

        let (store, runner, script, sessionID) = try makeRunner(
            project: project,
            turns: [AssistantTurn(text: "never")],
            coordinator: coordinator
        )

        await runner.prompt("blocked", delivery: .queue)
        await runner.run()

        #expect(try store.inboxRows(sessionID: sessionID).count == 1)
        #expect(try store.inboxRows(sessionID: sessionID)[0].text == "blocked")
        #expect(try store.messages(sessionID: sessionID).filter { $0.role == .assistant }.isEmpty)
        #expect(script.requests.isEmpty)
        #expect(try store.epochRecord(sessionID: sessionID, epochID: "epoch-1") == nil)
    }
}
