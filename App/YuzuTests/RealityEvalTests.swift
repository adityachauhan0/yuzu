import XCTest
import YuzuHarness
@testable import Yuzu

/// Product bar: a normal launch answers from uzu, not from a script.
///
/// Goodhart attacks that do not count as a pass:
/// - The model button no longer says "scripted".
/// - `usesLiveEngine` is hardcoded true.
/// - The test is skipped unless an env var is set.
/// - The prompt contains the secret and the stub echoes the prompt.
/// - `ScriptedTurn.backing` is flipped to `.uzu` (R0 forbids that).
@MainActor
final class RealityEvalTests: XCTestCase {
    func testR1_normalLaunchIsUzuTurn() async throws {
        unsetenv("YUZU_UI_ROUTE")
        unsetenv("YUZU_UI_THEME")
        let model = try AppModel.makeForLaunch()
        await model.prepareAdvisedModel()
        XCTAssertEqual(
            model.runner.modelBacking,
            .uzu,
            "Launch is \(model.runner.installedModelTypeName). A renamed label is not a model."
        )
        XCTAssertTrue(
            model.runner.installedModelTypeName.contains("YuzuModel.UzuTurn"),
            "Launch model is \(model.runner.installedModelTypeName), not YuzuModel.UzuTurn."
        )
    }

    func testR2_replyContainsFileNonceThePromptDoesNot() async throws {
        unsetenv("YUZU_UI_ROUTE")
        unsetenv("YUZU_UI_THEME")
        let model = try AppModel.makeForLaunch()
        await model.prepareAdvisedModel()
        let installed = model.runner.installedModelTypeName
        guard model.runner.modelBacking == .uzu, installed.contains("YuzuModel.UzuTurn") else {
            XCTFail("R2 refused: launch model is \(installed). Skipping would leave the suite green without a harness.")
            return
        }

        let nonce = "nonce-\(UUID().uuidString)"
        let session = try XCTUnwrap(try model.store.session(id: model.sessionID))
        try model.store.deleteMessages(sessionID: model.sessionID)
        var clean = session
        clean.modelMessageCursor = 0
        clean.epochID = "epoch-r2-\(UUID().uuidString)"
        try model.store.updateSession(clean)
        let secret = URL(fileURLWithPath: session.projectPath).appendingPathComponent("secret.txt")
        try nonce.write(to: secret, atomically: true, encoding: .utf8)
        let prompt = "Use the read tool on secret.txt. Reply with only the file contents."
        XCTAssertFalse(prompt.contains(nonce))

        await model.sendPrompt(prompt)
        let deadline = Date().addingTimeInterval(180)
        var answer = ""
        while Date() < deadline {
            let messages = (try? model.store.messages(sessionID: model.sessionID)) ?? []
            let fresh = messages.drop { $0.role != .user || $0.text != prompt }
            let turn = Array(fresh.dropFirst())
            if let last = turn.last(where: { $0.role == .assistant && !$0.text.isEmpty && $0.toolCalls.isEmpty }) {
                answer = last.text
                let sawRead = turn.contains { message in
                    message.toolCalls.contains { $0.name == "read" }
                }
                if answer.contains(nonce), sawRead {
                    return
                }
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        XCTFail("Live model did not read secret.txt and reply with \(nonce). Last new answer: \(answer)")
    }

    func testPermissionAskReachesTheWindowAndReplyUnblocksBash() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuzu-permission-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = try AppModel.makeForTesting(databaseURL: directory.appendingPathComponent("test.sqlite"))
        let bash = ToolCall(
            id: "c-bash",
            name: "bash",
            arguments: .object(["command": .string("echo hi")])
        )
        model.runner.useModel(ScriptedTurn(turns: [
            AssistantTurn(text: "", toolCalls: [bash]),
            AssistantTurn(text: "done"),
        ]))

        let run = Task { await model.sendPrompt("run echo") }
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, model.pendingPermission == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        let pending = try XCTUnwrap(model.pendingPermission, "The window never saw the permission ask.")
        XCTAssertEqual(pending.toolName, "bash")
        await model.replyToPending(.once)
        await run.value
        let messages = try model.store.messages(sessionID: model.sessionID)
        XCTAssertTrue(messages.contains { $0.role == .tool && $0.text.contains("Ran:") })
    }

    func testMemoryFromATurnIsIncludedUntilTheSwitchIsOff() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuzu-memory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = try AppModel.makeForTesting(databaseURL: directory.appendingPathComponent("test.sqlite"))
        model.runner.useModel(ScriptedTurn(turns: [AssistantTurn(text: "ok")]))
        model.setMemoryEnabled(true)
        let phrase = "remember the port is 4242"
        await model.sendPrompt(phrase)
        let included = try model.runner.contextCoordinator.loadUserInstructions()
        XCTAssertTrue(included?.contains("4242") == true)
        model.setMemoryEnabled(false)
        let excluded = try model.runner.contextCoordinator.loadUserInstructions()
        XCTAssertFalse(excluded?.contains("4242") == true)
    }

    func testLaunchRefusesTheScriptedStandIn() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuzu-standin-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = try AppModel.makeForTesting(databaseURL: directory.appendingPathComponent("test.sqlite"))
        model.testingRefuseScriptedReplies()
        await model.sendPrompt("hello from the stand-in")
        let messages = try model.store.messages(sessionID: model.sessionID)
        XCTAssertTrue(messages.isEmpty, "The scripted stand-in answered a normal prompt.")
        XCTAssertEqual(model.toastMessage, "Could not download a model")
    }

    func testScheduleCommandDoesNotRunTheModel() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuzu-schedule-cmd-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = try AppModel.makeForTesting(databaseURL: directory.appendingPathComponent("test.sqlite"))
        model.runner.useModel(ScriptedTurn(turns: [AssistantTurn(text: "should not run")]))
        await model.sendPrompt("/schedule Weekdays at 8:00 AM")
        XCTAssertEqual(model.coworkDestination, .scheduled)
        XCTAssertTrue(model.scheduleComposerOpen)
        XCTAssertEqual(model.scheduleComposerTime, "Weekdays at 8:00 AM")
        let messages = try model.store.messages(sessionID: model.sessionID)
        XCTAssertTrue(messages.isEmpty)
    }

    func testFontChoicesResolveToTheFamiliesTheUIUses() {
        XCTAssertEqual(YuzuFonts.interfaceFamily("System"), "")
        XCTAssertEqual(YuzuFonts.interfaceFamily("Serif"), "Georgia")
        XCTAssertEqual(YuzuFonts.interfaceFamily("OpenDyslexic"), "OpenDyslexic")
        XCTAssertEqual(YuzuFonts.codeFamily(""), "")
        XCTAssertEqual(YuzuFonts.codeFamily(" JetBrains Mono "), "JetBrains Mono")
    }
}
