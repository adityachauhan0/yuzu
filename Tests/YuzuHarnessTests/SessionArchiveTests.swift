import Foundation
import Testing
import YuzuHarness

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
}
