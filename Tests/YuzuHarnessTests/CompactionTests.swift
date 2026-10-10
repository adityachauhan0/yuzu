import Foundation
import Testing
@testable import YuzuHarness

@Suite(.readsMCPHub)
struct CompactionTests {
    private func makeWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuzu-compaction-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func testCompactionSession(
        projectPath: String,
        epochID: String = "epoch-1"
    ) -> SessionRecord {
        SessionRecord(
            id: "session-1",
            projectPath: projectPath,
            agentID: "build",
            modelIdentifier: "test",
            epochID: epochID,
            stepCount: 0,
            supportsMultipleToolCalls: true,
            status: .idle,
            modelMessageCursor: 0,
            contextLength: 1_000,
            compactionBufferTokens: 200,
            compactionKeepTokens: 100
        )
    }

    private func makeRunner(
        project: URL,
        turns: [AssistantTurn]
    ) throws -> (HarnessStore, SessionRunner, ScriptedTurn, String) {
        let dbURL = project.appendingPathComponent("session.sqlite")
        let store = try HarnessStore(path: dbURL.path)
        let session = testCompactionSession(projectPath: project.path)
        try store.insertSession(session)
        let script = ScriptedTurn(turns: turns)
        let runner = SessionRunner(sessionID: session.id, store: store, model: script)
        return (store, runner, script, session.id)
    }

    private func seedOverflowHistory(
        store: HarnessStore,
        sessionID: String,
        epochID: String
    ) throws {
        let padding = String(repeating: "z", count: 900)
        try store.appendMessage(sessionID: sessionID, message: .user("DROPME"), epochID: epochID)
        for index in 0..<4 {
            try store.appendMessage(
                sessionID: sessionID,
                message: .user("bulk-\(index) \(padding)"),
                epochID: epochID
            )
            try store.appendMessage(
                sessionID: sessionID,
                message: .assistant(AssistantTurn(text: "ack-\(index)")),
                epochID: epochID
            )
        }
        try store.appendMessage(
            sessionID: sessionID,
            message: .user("KEEPME"),
            epochID: epochID
        )
    }

    private func projectedTexts(
        store: HarnessStore,
        runner: SessionRunner,
        sessionID: String
    ) throws -> [String] {
        let session = try #require(try store.session(id: sessionID))
        return try runner.contextCoordinator.projectedHistory(
            store: store,
            sessionID: sessionID,
            session: session
        ).map(\.text)
    }

    @Test func K1_overflowRunsSummaryTurn() async throws {
        let project = try makeWorkspace()
        let (store, runner, script, sessionID) = try makeRunner(
            project: project,
            turns: [
                AssistantTurn(text: "## Goal\ncompacted"),
                AssistantTurn(text: "done"),
            ]
        )
        try seedOverflowHistory(store: store, sessionID: sessionID, epochID: "epoch-1")

        await runner.run()

        let session = try #require(try store.session(id: sessionID))
        #expect(session.epochID != "epoch-1")
        let summaryRequests = script.requests.filter(Compaction.isSummaryTurnRequest)
        #expect(summaryRequests.count == 1)
        #expect(summaryRequests[0].tools.isEmpty)
        #expect(
            summaryRequests[0].delta.contains { message in
                message.role == .user && message.text.contains(Compaction.summaryInstruction)
            }
        )
    }

    @Test func K2_recentTailSurvives() async throws {
        let project = try makeWorkspace()
        let (store, runner, _, sessionID) = try makeRunner(
            project: project,
            turns: [
                AssistantTurn(text: "summary body"),
                AssistantTurn(text: "ok"),
            ]
        )
        try seedOverflowHistory(store: store, sessionID: sessionID, epochID: "epoch-1")

        await runner.run()

        let texts = try projectedTexts(store: store, runner: runner, sessionID: sessionID)
        let joined = texts.joined(separator: "\n")
        #expect(joined.contains("summary body"))
        #expect(joined.contains("KEEPME"))
        #expect(!texts.contains("DROPME"))
    }

    @Test func K3_replayAfterReset() async throws {
        let project = try makeWorkspace()
        let (store, runner, script, sessionID) = try makeRunner(
            project: project,
            turns: [
                AssistantTurn(text: "summary"),
                AssistantTurn(text: "after"),
            ]
        )
        try seedOverflowHistory(store: store, sessionID: sessionID, epochID: "epoch-1")

        await runner.run()

        let session = try #require(try store.session(id: sessionID))
        #expect(script.resetEpochs.contains(session.epochID))
        #expect(script.resetWhenRequestCount == [1])
        let summaryIndex = try #require(script.requests.firstIndex(where: Compaction.isSummaryTurnRequest))
        #expect(summaryIndex == 0)
        #expect(script.requests.count >= 2)
        #expect(!Compaction.isSummaryTurnRequest(script.requests[1]))
    }

    @Test func K4_summaryMustCarryFacts() async throws {
        let project = try makeWorkspace()
        let (store, runner, script, sessionID) = try makeRunner(
            project: project,
            turns: [
                AssistantTurn(text: "summary without the fact token"),
                AssistantTurn(text: "done"),
            ]
        )
        try seedOverflowHistory(store: store, sessionID: sessionID, epochID: "epoch-1")

        await runner.run()

        let summaryRequest = try #require(script.requests.first(where: Compaction.isSummaryTurnRequest))
        let prompt = summaryRequest.delta.map(\.text).joined(separator: "\n")
        #expect(prompt.contains("DROPME"))
    }
}
