import Foundation
import Testing
import YuzuHarness

@Suite(.readsMCPHub)
struct SessionArchiveTests {
    @Test func exportAndImportAppends() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuzu-archive-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = try HarnessStore(path: root.appendingPathComponent("session.sqlite").path)
        try store.insertSession(
            SessionRecord(
                id: "main",
                projectPath: root.path,
                agentID: "build",
                modelIdentifier: "model",
                epochID: "epoch-1",
                stepCount: 0,
                supportsMultipleToolCalls: true,
                status: .idle,
                modelMessageCursor: 0
            )
        )
        try store.appendMessage(
            sessionID: "main",
            message: StoredMessage(role: .user, text: "hello"),
            epochID: "epoch-1"
        )
        let exported = try store.exportSessionDocuments()
        let data = try JSONEncoder().encode(exported)
        let decoded = try JSONDecoder().decode([SessionDocument].self, from: data)
        try store.importSessionDocuments(decoded)
        let sessions = try store.allSessions()
        #expect(sessions.count == 2)
        let imported = try #require(sessions.first { $0.id != "main" })
        let messages = try store.messages(sessionID: imported.id)
        #expect(messages.map(\.text) == ["hello"])
    }

    @Test func tasksAreRealSessionsWithTitlesPinsAndDeletes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuzu-tasks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = try HarnessStore(path: root.appendingPathComponent("session.sqlite").path)
        for id in ["a", "b"] {
            try store.insertSession(
                SessionRecord(
                    id: id, projectPath: root.path, agentID: "build", modelIdentifier: "model-\(id)",
                    epochID: "epoch-\(id)", stepCount: 0, supportsMultipleToolCalls: true,
                    status: .idle, modelMessageCursor: 0
                )
            )
        }
        try store.appendMessage(sessionID: "a", message: StoredMessage(role: .user, text: "fix the parser\nmore"))
        try store.appendMessage(
            sessionID: "a",
            message: StoredMessage(role: .assistant, text: "done", outputTokens: 12)
        )
        try store.appendMessage(sessionID: "b", message: StoredMessage(role: .user, text: "write docs"))

        var summaries = try store.sessionSummaries()
        #expect(summaries.map(\.id) == ["b", "a"])
        #expect(summaries.first { $0.id == "a" }?.displayTitle == "fix the parser")
        #expect(summaries.first { $0.id == "a" }?.messageCount == 2)

        try store.setSessionTitle(id: "a", title: "Parser")
        try store.setSessionPinned(id: "a", pinned: true)
        summaries = try store.sessionSummaries()
        let a = try #require(summaries.first { $0.id == "a" })
        #expect(a.displayTitle == "Parser")
        #expect(a.pinned)

        let usage = try store.usageRows()
        #expect(usage.count == 3)
        #expect(usage.allSatisfy { $0.at != nil })
        #expect(usage.compactMap(\.outputTokens) == [12])
        #expect(Set(usage.map(\.modelIdentifier)) == ["model-a", "model-b"])

        try store.deleteSession(id: "a")
        #expect(try store.sessionSummaries().map(\.id) == ["b"])
        #expect(try store.messages(sessionID: "a").isEmpty)
    }
}
