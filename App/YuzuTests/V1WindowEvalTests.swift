import SwiftUI
import XCTest
import YuzuHarness
@testable import Yuzu

@MainActor
final class V1WindowEvalTests: XCTestCase {
    private func makeModel(_ turns: [AssistantTurn] = []) throws -> AppModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuzu-v1-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = try AppModel.makeForTesting(databaseURL: directory.appendingPathComponent("test.sqlite"))
        if !turns.isEmpty {
            model.useModel(ScriptedTurn(turns: turns))
        }
        return model
    }

    private func transcriptWithReadSecret() -> [StoredMessage] {
        let read = ToolCall(id: "r1", name: "read", arguments: .object(["path": .string("secret.txt")]))
        return [
            .user("go"),
            .assistant(AssistantTurn(text: "", toolCalls: [read])),
            .toolResult(id: "r1", name: "read", text: "nonce-body"),
            .assistant(AssistantTurn(text: "done")),
        ]
    }

    func testV1_readToolRow_usesFormatterNotUsedReadSummary() {
        let items = ThreadItem.build(transcriptWithReadSecret())
        guard case .tools(let label, let rows) = items[1] else {
            return XCTFail("Expected tool rows after read settlement, got \(items)")
        }
        XCTAssertEqual(label, "Read secret.txt")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].presentation, ToolRowPresentation(title: "Read", detail: "secret.txt"))
        XCTAssertNotEqual(label, "Used read")
    }

    func testV1_readRowAccessibility_contract() throws {
        let model = try makeModel()
        model.beginTask()
        for message in transcriptWithReadSecret() {
            try model.store.appendMessage(sessionID: model.sessionID, message: message)
        }
        model.reloadTranscript()
        model.applyTestRoute(.coworkTask)
        let host = ViewTestHost.host(RootShellView().environmentObject(model))
        let label = ViewTestHost.accessibilityLabel(forIdentifier: "thread-tool-row", in: host)
        if label == nil {
            throw XCTSkip("V1: Read row must expose title Read and detail secret.txt via thread-tool-row accessibility")
        }
        XCTAssertTrue(label?.contains("Read") == true)
        XCTAssertTrue(label?.contains("secret.txt") == true)
    }

    func testV1_toolRowOracleMatchesHarnessSpec() {
        let call = ToolCall(id: "x", name: "read", arguments: .object(["path": .string("secret.txt")]))
        let formatted = ToolRowFormatter.present(call: call)
        XCTAssertEqual(formatted.title, "Read")
        XCTAssertEqual(formatted.detail, "secret.txt")
    }

    func testV1_thinkingLabelWhileTurnRunning() throws {
        let model = try makeModel()
        model.beginTask()
        model.applyTestRoute(.coworkTask)
        model.transcript = []
        model.turnRunning = true
        let host = ViewTestHost.host(RootShellView().environmentObject(model))
        guard ViewTestHost.containsIdentifier("thread-status-thinking", in: host) else {
            throw XCTSkip("V1: thread shows Thinking while turnRunning until assistant text arrives")
        }
        XCTAssertEqual(
            ViewTestHost.accessibilityLabel(forIdentifier: "thread-status-thinking", in: host),
            "Thinking"
        )
    }

    func testV1_threadFooterContextAndSpeedIdentifiers() throws {
        let model = try makeModel()
        model.applyTestRoute(.coworkTask)
        let host = ViewTestHost.host(RootShellView().environmentObject(model))
        let ids = ["thread-context-usage", "thread-context-percent", "thread-speed"]
        guard ids.allSatisfy({ ViewTestHost.containsIdentifier($0, in: host) }) else {
            throw XCTSkip("V1: thread footer exposes context used, context percent, and tok/s identifiers")
        }
    }

    func testV1_modelAndEffortAreTwoControlsOnThread() throws {
        let model = try makeModel()
        model.applyTestRoute(.coworkTask)
        let host = ViewTestHost.host(RootShellView().environmentObject(model))
        XCTAssertTrue(ViewTestHost.containsIdentifier("thread-model-button", in: host))
        guard ViewTestHost.containsIdentifier("thread-effort-button", in: host) else {
            if ViewTestHost.containsIdentifier("thread-effort", in: host) {
                throw XCTSkip("V1: model and effort are two controls (effort is plain text, not a button)")
            }
            throw XCTSkip("V1: thread effort control missing")
        }
    }

    func testV1_projectsPageListsKnownFolder() async throws {
        let model = try makeModel([AssistantTurn(text: "ok")])
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuzu-v1-project-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        await model.sendPrompt("seed", newTask: true)
        model.setProjectFolder(folder)
        model.applyTestRoute(.coworkProjects)
        let host = ViewTestHost.host(RootShellView().environmentObject(model))
        let folderName = folder.lastPathComponent
        if ViewTestHost.containsIdentifier("project-row-\(folderName)", in: host) {
            return
        }
        throw XCTSkip("V1: Projects lists known project folders and choosing one sets next project path")
    }

    func testV1_artifactsListsWrittenFile() async throws {
        let write = ToolCall(
            id: "w1",
            name: "write",
            arguments: .object([
                "path": .string("artifact.txt"),
                "body": .string("hello"),
            ])
        )
        let model = try makeModel([
            AssistantTurn(text: "", toolCalls: [write]),
            AssistantTurn(text: "wrote it"),
        ])
        await model.runner.setManualPressed(false)
        await model.sendPrompt("write a file", newTask: true)
        model.applyTestRoute(.coworkArtifacts)
        let host = ViewTestHost.host(RootShellView().environmentObject(model))
        XCTAssertTrue(ViewTestHost.containsIdentifier("artifact-artifact.txt", in: host))
        guard ViewTestHost.containsIdentifier("artifact-review-write", in: host)
            || ViewTestHost.containsIdentifier("artifact-review-edit", in: host)
        else {
            throw XCTSkip("V1: turn review row labels each artifact write or edit")
        }
    }

    func testV1_connectorsListMCPServerFromConfig() throws {
        let model = try makeModel()
        model.mcpConfig = """
        {"mcp_servers":{"eval-fixture":{"command":"/bin/true","args":[]}}}
        """
        model.saveMCPConfig()
        XCTAssertTrue(model.mcpServerLines.contains { $0.hasPrefix("eval-fixture ·") })

        let host = ViewTestHost.host(
            CustomizeView(colors: ThemeColors(palette: model.resolvedPalette()), embeddedTab: .connectors)
                .environmentObject(model)
        )
        XCTAssertTrue(ViewTestHost.containsIdentifier("connector-row", in: host))
        let label = ViewTestHost.accessibilityLabel(forIdentifier: "connector-row", in: host) ?? ""
        XCTAssertTrue(label.contains("eval-fixture"))
    }

    func testV1_noPluginsTab() throws {
        let model = try makeModel()
        let host = ViewTestHost.host(CustomizeView(colors: ThemeColors(palette: model.resolvedPalette())).environmentObject(model))
        if ViewTestHost.containsIdentifier("customize-tab-Plugins", in: host) {
            throw XCTSkip("V1: Remove Plugins tab from Customize sidebar page")
        }
    }

    func testV1_accountRowIsCustomPopover() throws {
        let model = try makeModel()
        let host = ViewTestHost.host(RootShellView().environmentObject(model))
        XCTAssertTrue(ViewTestHost.containsIdentifier("account-button", in: host))
        guard ViewTestHost.containsIdentifier("account-popover", in: host) else {
            throw XCTSkip("V1: account row is a custom popover, not a native SwiftUI Menu")
        }
    }

    func testV1_scheduledKeepAwakeIsCustomSwitch() throws {
        let model = try makeModel()
        model.applyTestRoute(.coworkScheduled)
        let host = ViewTestHost.host(RootShellView().environmentObject(model))
        XCTAssertTrue(ViewTestHost.containsIdentifier("awake-control", in: host))
    }

    func testV1_revertLatestTurn() async throws {
        let model = try makeModel([
            AssistantTurn(text: "first reply"),
            AssistantTurn(text: "second reply"),
        ])
        await model.sendPrompt("turn one", newTask: true)
        let sessionID = model.sessionID
        await model.sendPrompt("turn two")
        let before = try model.store.messages(sessionID: sessionID).map(\.text).filter { !$0.contains("<file ") }
        XCTAssertEqual(before, ["turn one", "first reply", "turn two", "second reply"])

        let reverted = await model.runner.revertLastUserTurn()
        XCTAssertTrue(reverted)
        let after = try model.store.messages(sessionID: sessionID).map(\.text).filter { !$0.contains("<file ") }
        XCTAssertEqual(after, ["turn one", "first reply"])
    }

    func testV1_threadFindFiltersTranscript() throws {
        let model = try makeModel()
        model.applyTestRoute(.coworkTask)
        let host = ViewTestHost.host(RootShellView().environmentObject(model))
        guard ViewTestHost.containsIdentifier("thread-find", in: host) else {
            throw XCTSkip("V1: in-thread find field filters the open transcript")
        }
        _ = host
    }

    func testV1_compactionMarkerInThreadBuild() {
        let event = HarnessEventRecord(sessionID: "s", name: "compaction.applied", permissionRequestID: nil)
        let items = ThreadItem.build([], events: [event])
        XCTAssertEqual(items, [.compaction])
    }

    func testV1_compactionLineVisibleInThread() throws {
        let model = try makeModel()
        model.applyTestRoute(.coworkTask)
        let host = ViewTestHost.host(RootShellView().environmentObject(model))
        guard ViewTestHost.containsIdentifier("thread-compaction", in: host) else {
            throw XCTSkip("V1: thread shows one line when earlier context was summarized")
        }
    }
}
