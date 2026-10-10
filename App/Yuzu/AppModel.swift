import Foundation
import SwiftUI
import YuzuHarness

enum WorkspaceMode: String, Sendable {
    case cowork = "Cowork"
    case code = "Code"
}

enum CoworkDestination: String, Sendable, CaseIterable {
    case new = "New"
    case projects = "Projects"
    case artifacts = "Artifacts"
    case scheduled = "Scheduled"
    case customize = "Customize"
    case task = "Task"
}

enum SettingsTab: String, Sendable, CaseIterable {
    case general = "General"
    case code = "Code"
    case developer = "Developer"
}

enum InspectorPresentation: String, Sendable {
    case beside
    case overlay
}

@MainActor
final class AppModel: ObservableObject {
    static let disclaimer =
        "Yuzu is on-device AI. its not the best. Please double check responses."

    @Published var workspaceMode: WorkspaceMode = .code
    @Published var coworkDestination: CoworkDestination = .new
    @Published var theme: AppTheme = .dark
    @Published var settingsPresented = false
    @Published var settingsTab: SettingsTab = .general
    @Published var manualPressed = true
    @Published var showTaskThread = false
    @Published var inspectorOpen = true
    @Published var contentWidth: CGFloat = 1440
    @Published var sidebarCollapsed = false
    @Published var codeFolderName = "Select folder…"
    @Published var keepAwake = false

    let store: HarnessStore
    let runner: SessionRunner
    let sessionID: String

    private init(store: HarnessStore, runner: SessionRunner, sessionID: String) {
        self.store = store
        self.runner = runner
        self.sessionID = sessionID
    }

    static func makeForLaunch() throws -> AppModel {
        try make(sessionDirectory: defaultSupportDirectory())
    }

    static func makeForTesting(databaseURL: URL) throws -> AppModel {
        try make(sessionDirectory: databaseURL.deletingLastPathComponent())
    }

    private static func make(sessionDirectory: URL) throws -> AppModel {
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        let dbURL = sessionDirectory.appendingPathComponent("yuzu.sqlite")
        let store = try HarnessStore(path: dbURL.path)
        let sessionID = "main"
        let project = sessionDirectory.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let session = SessionRecord(
            id: sessionID,
            projectPath: project.path,
            agentID: "build",
            modelIdentifier: "scripted",
            epochID: "epoch-1",
            stepCount: 0,
            supportsMultipleToolCalls: true,
            status: SessionStatus.idle,
            modelMessageCursor: 0,
            manualPressed: true
        )
        if try store.session(id: sessionID) == nil {
            try store.insertSession(session)
        }
        let model = ScriptedTurn(turns: [AssistantTurn(text: "")])
        let runner = SessionRunner(sessionID: sessionID, store: store, model: model)
        return AppModel(store: store, runner: runner, sessionID: sessionID)
    }

    private static func defaultSupportDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Yuzu", isDirectory: true)
    }

    func selectCowork(_ destination: CoworkDestination) {
        workspaceMode = .cowork
        coworkDestination = destination
        if destination == .task {
            showTaskThread = true
        }
    }

    func selectCode() {
        workspaceMode = .code
    }

    func openSettings(tab: SettingsTab = .general) {
        settingsTab = tab
        settingsPresented = true
    }

    func toggleManual() async {
        manualPressed.toggle()
        await runner.setManualPressed(manualPressed)
    }

    func sendPrompt(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await runner.prompt(trimmed, delivery: .steer)
        Task { await runner.run() }
        if workspaceMode == .cowork {
            showTaskThread = true
            coworkDestination = .task
        }
    }

    func permissionEffect(manualPressed: Bool) -> PermissionEffect {
        PermissionEvaluator.effect(
            agentID: "build",
            action: "edit",
            resource: "*",
            savedAllows: [],
            manualPressed: manualPressed
        )
    }

    func inspectorPresentation(width: CGFloat) -> InspectorPresentation {
        width < 1240 ? .overlay : .beside
    }

    func resolvedPalette() -> Tokens.Palette {
        theme.palette
    }

    func motionDurations(reduceMotion: Bool) -> (hoverMs: Int, drawerMs: Int) {
        MotionTiming.durations(reduceMotion: reduceMotion)
    }

    var hasProjects: Bool { false }
    var hasArtifacts: Bool { false }
    var hasPinnedItems: Bool { false }
    var recentTaskTitles: [String] { [] }
    var totalTokenCount: Int { 0 }

    var modelDisplayName: String {
        (try? store.session(id: sessionID)?.modelIdentifier) ?? "scripted"
    }

    var gatsbyUsageNote: String {
        let multiple = max(1, totalTokenCount / 62_000)
        return "You've used ~\(multiple)× more tokens than The Great Gatsby."
    }

    func applyTestRoute(_ route: UITestRoute) {
        settingsPresented = false
        showTaskThread = false
        switch route {
        case .code:
            workspaceMode = .code
        case .coworkNew:
            workspaceMode = .cowork
            coworkDestination = .new
        case .coworkProjects:
            workspaceMode = .cowork
            coworkDestination = .projects
        case .coworkArtifacts:
            workspaceMode = .cowork
            coworkDestination = .artifacts
        case .coworkScheduled:
            workspaceMode = .cowork
            coworkDestination = .scheduled
        case .coworkCustomize:
            workspaceMode = .cowork
            coworkDestination = .customize
        case .coworkTask:
            workspaceMode = .cowork
            coworkDestination = .task
            showTaskThread = true
        case .settingsCode:
            openSettings(tab: .code)
        }
    }
}

enum UITestRoute: CaseIterable, Sendable {
    case code
    case coworkNew
    case coworkProjects
    case coworkArtifacts
    case coworkScheduled
    case coworkCustomize
    case coworkTask
    case settingsCode
}
