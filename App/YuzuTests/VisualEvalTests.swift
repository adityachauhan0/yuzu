import XCTest
import SwiftUI
import YuzuHarness
@testable import Yuzu

@MainActor
final class VisualEvalTests: XCTestCase {
    private let forbidden = [
        "Claude Code",
        "Anthropic",
        "GPT 6 Luna",
        "Claude Opus",
        "graph-engineering",
        "tldraw",
        "adityachauhan",
        "not shown in the supplied reference",
        "were not provided in the reference",
    ]

    private func makeModel() throws -> AppModel {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuzu-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try AppModel.makeForTesting(databaseURL: dir.appendingPathComponent("test.sqlite"))
    }

    private func rootView(model: AppModel) -> some View {
        RootShellView().environmentObject(model)
    }

    func testV1_forbiddenCopyAbsent() throws {
        let model = try makeModel()
        for theme in AppTheme.allCases {
            model.theme = theme
            for route in UITestRoute.allCases {
                model.applyTestRoute(route)
                for width in [1100, 1440] {
                    let host = ViewTestHost.host(rootView(model: model), size: CGSize(width: width, height: 900))
                    let strings = ViewTestHost.collectAccessibilityStrings(from: host)
                    let blob = strings.joined(separator: "\n")
                    for word in forbidden {
                        XCTAssertFalse(blob.contains(word), "Found \(word) on \(route) \(theme) \(width)")
                    }
                }
            }
        }
    }

    private let disclaimerCopy =
        "Yuzu is on-device AI. its not the best. Please double check responses."

    func testV2_disclaimerExact() throws {
        let model = try makeModel()
        model.applyTestRoute(.coworkTask)
        let host = ViewTestHost.host(rootView(model: model))
        XCTAssertTrue(ViewTestHost.containsIdentifier("task-view", in: host))
        XCTAssertTrue(ViewTestHost.containsIdentifier("task-disclaimer", in: host))
        XCTAssertEqual(
            ViewTestHost.accessibilityLabel(forIdentifier: "task-disclaimer", in: host),
            disclaimerCopy
        )
    }

    func testV3_codeTabShowsAppearance() throws {
        let model = try makeModel()
        model.applyTestRoute(.settingsCode)
        let host = ViewTestHost.host(rootView(model: model))
        XCTAssertTrue(ViewTestHost.containsIdentifier("settings-code-appearance-heading", in: host))
        let strings = ViewTestHost.collectAccessibilityStrings(from: host).joined(separator: "\n")
        XCTAssertFalse(strings.contains("Settings for this section are not shown in the supplied reference."))
    }

    func testV4_emptyStates() throws {
        let model = try makeModel()
        model.applyTestRoute(.coworkArtifacts)
        var host = ViewTestHost.host(rootView(model: model))
        XCTAssertTrue(ViewTestHost.containsIdentifier("panel-No artifacts yet", in: host))

        model.applyTestRoute(.coworkProjects)
        host = ViewTestHost.host(rootView(model: model))
        XCTAssertTrue(ViewTestHost.containsIdentifier("panel-No project yet", in: host))

        model.applyTestRoute(.coworkCustomize)
        host = ViewTestHost.host(rootView(model: model))
        XCTAssertTrue(ViewTestHost.containsIdentifier("skills-banner", in: host))
        XCTAssertEqual(
            ViewTestHost.accessibilityLabel(forIdentifier: "skills-banner", in: host),
            "Skills teach Yuzu how you work."
        )

        model.applyTestRoute(.code)
        host = ViewTestHost.host(rootView(model: model))
        XCTAssertTrue(ViewTestHost.containsIdentifier("code-speed", in: host))
        XCTAssertEqual(
            ViewTestHost.accessibilityLabel(forIdentifier: "code-speed", in: host),
            "speed —"
        )
    }

    func testV5_darkAndLightTokens() throws {
        let model = try makeModel()
        model.theme = .dark
        XCTAssertEqual(model.resolvedPalette().canvas, Tokens.dark.canvas)
        XCTAssertEqual(model.resolvedPalette().text, Tokens.dark.text)
        XCTAssertEqual(model.resolvedPalette().accent, Tokens.dark.accent)
        model.theme = .light
        XCTAssertEqual(model.resolvedPalette().canvas, Tokens.light.canvas)
        XCTAssertEqual(model.resolvedPalette().text, Tokens.light.text)
        XCTAssertEqual(model.resolvedPalette().accent, Tokens.light.accent)
    }

    func testV6_reducedMotion() throws {
        let model = try makeModel()
        let reduced = model.motionDurations(reduceMotion: true)
        XCTAssertEqual(reduced.hoverMs, 0)
        XCTAssertEqual(reduced.drawerMs, 0)
        let normal = model.motionDurations(reduceMotion: false)
        XCTAssertEqual(normal.hoverMs, Tokens.hoverDurationMs)
        XCTAssertEqual(normal.drawerMs, Tokens.drawerDurationMs)
    }

    func testV7_inspectorOverlaysNarrow() throws {
        let model = try makeModel()
        model.applyTestRoute(.coworkTask)
        model.inspectorOpen = true

        model.contentWidth = 1100
        let host = ViewTestHost.host(rootView(model: model), size: CGSize(width: 1100, height: 900))
        XCTAssertTrue(ViewTestHost.containsIdentifier("task-view", in: host))
        XCTAssertTrue(ViewTestHost.containsIdentifier("inspector-layout-overlay", in: host))
        XCTAssertFalse(ViewTestHost.containsIdentifier("inspector-layout-beside", in: host))

        model.contentWidth = 1400
        let wide = ViewTestHost.host(rootView(model: model), size: CGSize(width: 1400, height: 900))
        XCTAssertTrue(ViewTestHost.containsIdentifier("inspector-layout-beside", in: wide))
        XCTAssertFalse(ViewTestHost.containsIdentifier("inspector-layout-overlay", in: wide))
    }

    func testV9_emptyCoworkSubmitToast() async throws {
        let model = try makeModel()
        model.applyTestRoute(.coworkNew)
        await model.submitCoworkHomeTask("   ")
        XCTAssertEqual(model.toastMessage, "Write a task to get started.")
        let host = ViewTestHost.host(rootView(model: model))
        XCTAssertTrue(ViewTestHost.containsIdentifier("toast", in: host))
        XCTAssertEqual(
            ViewTestHost.accessibilityLabel(forIdentifier: "toast", in: host),
            "Write a task to get started."
        )
    }

    func testV8_manualAndLocal() async throws {
        let model = try makeModel()
        model.applyTestRoute(.code)
        var host = ViewTestHost.host(rootView(model: model))
        XCTAssertFalse(ViewTestHost.containsIdentifier("code-local", in: host))
        XCTAssertTrue(ViewTestHost.containsIdentifier("code-folder", in: host))
        XCTAssertTrue(ViewTestHost.containsIdentifier("code-manual", in: host))
        XCTAssertEqual(model.permissionPosture, .workspaceRead)
        XCTAssertEqual(model.permissionEffect(for: .workspaceRead, action: "edit"), .ask)
        XCTAssertEqual(model.permissionEffect(for: .workspaceRead, action: "bash"), .ask)

        await model.toggleManual()
        XCTAssertEqual(model.permissionPosture, .workspaceWrite)
        XCTAssertEqual(model.permissionEffect(for: .workspaceWrite, action: "edit"), .allow)
        XCTAssertEqual(model.permissionEffect(for: .workspaceWrite, action: "bash"), .ask)

        await model.toggleManual()
        XCTAssertEqual(model.permissionPosture, .yolo)
        XCTAssertEqual(model.permissionEffect(for: .yolo, action: "edit"), .allow)
        XCTAssertEqual(model.permissionEffect(for: .yolo, action: "bash"), .allow)

        await model.toggleManual()
        XCTAssertEqual(model.permissionPosture, .workspaceRead)

        host = ViewTestHost.host(rootView(model: model))
        XCTAssertTrue(ViewTestHost.containsIdentifier("code-manual", in: host))
    }

    func testRequiredAccessibilityIdentifiers() throws {
        let model = try makeModel()
        let host = ViewTestHost.host(rootView(model: model))
        for id in [
            "sidebar",
            "mode-switch-cowork",
            "mode-switch-code",
            "nav-new",
            "nav-projects",
            "nav-artifacts",
            "nav-scheduled",
            "nav-customize",
            "code-view",
        ] {
            XCTAssertTrue(ViewTestHost.containsIdentifier(id, in: host), "Missing \(id)")
        }
        model.applyTestRoute(.coworkNew)
        let home = ViewTestHost.host(rootView(model: model))
        XCTAssertTrue(ViewTestHost.containsIdentifier("home", in: home))
        model.applyTestRoute(.coworkTask)
        let task = ViewTestHost.host(rootView(model: model))
        XCTAssertTrue(ViewTestHost.containsIdentifier("task-view", in: task))
        model.applyTestRoute(.settingsCode)
        let settings = ViewTestHost.host(rootView(model: model))
        XCTAssertTrue(ViewTestHost.containsIdentifier("settings-dialog", in: settings))
    }
}
