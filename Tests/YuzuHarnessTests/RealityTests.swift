import Foundation
import Testing
import YuzuHarness

/// Guards the stand-in. These pass today on purpose.
/// A green R0 does not mean the app is a harness. R1 and R2 live on the app target and must fail until launch uses uzu.
struct RealityTests {
    @Test func R0_scriptedTurnIsNotALiveEngine() {
        let model = ScriptedTurn(turns: [AssistantTurn(text: "scripted-canned-line")])
        #expect(model.backing == .scripted)
        #expect(String(reflecting: type(of: model)).contains("ScriptedTurn"))
        #expect(!String(reflecting: type(of: model)).contains("UzuTurn"))
    }

    @Test func R0_scriptedTurnCannotInventAFileNonce() async throws {
        let nonce = "nonce-\(UUID().uuidString)"
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuzu-r0-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try nonce.write(to: root.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)

        let model = ScriptedTurn(turns: [AssistantTurn(text: "")])
        let request = TurnRequest(
            epochID: "epoch",
            delta: [.user("Read secret.txt and reply with its contents.")],
            tools: [],
            toolTurnLimit: 0,
            reasoningEffort: .high,
            contextLength: 4096
        )
        var text = ""
        for try await event in model.complete(request) {
            if case .text(let delta) = event {
                text += delta
            }
            if case .finished(let turn) = event {
                text = turn.text
            }
        }
        #expect(!text.contains(nonce))
    }
}
