import Foundation
import os
import AppKit
import SwiftUI
import UserNotifications
import YuzuHarness
import YuzuModel

struct UsageMetrics: Equatable {
    var sessions: Int
    var messages: Int
    var tokens: Int
    var activeDays: Int
    var peakHour: String
    var favoriteModel: String
}

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

enum SettingsAnchor: Hashable {
    case mcpConfig
    case inference
}

enum SettingsTab: String, Sendable, CaseIterable {
    case general = "General"
    case privacy = "Privacy"
    case usage = "Usage"
    case code = "Code"
    case cowork = "Cowork"
    case importExport = "Import & export"
    case system = "System"
    case developer = "Developer"
    case skills = "Skills"
    case connectors = "Connectors"
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
    /// A Code task is open in the thread. The Code mode switch returns to the Code home.
    @Published var codeThreadOpen = false
    @Published var coworkDestination: CoworkDestination = .new
    @Published var theme: AppTheme = .dark { didSet { saveAppearance() } }
    @Published var settingsPresented = false
    @Published var settingsTab: SettingsTab = .general
    @Published var permissionPosture: PermissionPosture = .workspaceRead
    var manualPressed: Bool { permissionPosture == .workspaceRead }
    @Published var showTaskThread = false
    @Published var inspectorOpen = true
    @Published var contentWidth: CGFloat = 1440
    @Published var sidebarCollapsed = false
    @Published var codeFolderName = "Sandbox"
    @Published var keepAwake = false
    @Published var reasoningEffort: ReasoningEffort = .high
    @Published var coworkProjectName = "No project"
    @Published var toastMessage: String?
    @Published var downloadStatus: String?
    @Published var searchOpen = false
    @Published var requestedSkill: String?
    let escapeStack = EscapeStack()
    let outsideClicks = OutsideClickStack()
    @Published var coworkSeed: String?
    @Published var installedModelName: String?
    private(set) var installedModelIdentifier: String?
    @Published var speedLabel = "—"
    /// Engine token total for the turn on screen, including prompt, cache, and generated tokens.
    @Published private(set) var liveContextLabel: String?
    /// Transcript count when the current send started, so Thinking is not hidden by the previous reply.
    private var replyFloor = 0
    @Published var scheduledTasks: [ScheduledTaskRecord] = []
    @Published var workDescription = "Select"
    @Published var settingsAnchor: SettingsAnchor?
    @Published private(set) var avatarRevision = 0

    var avatarFileURL: URL {
        supportDirectory.appendingPathComponent("avatar.png")
    }

    func saveAvatar(png data: Data) {
        try? data.write(to: avatarFileURL, options: .atomic)
        avatarRevision += 1
    }
    @Published var yuzuInstructions = ""
    @Published var chatFont = "Source Serif" { didSet { saveAppearance() } }
    @Published var motionSetting = "System" { didSet { saveAppearance() } }
    @Published var responseCompletions = false
    @Published var codeFont = "" { didSet { saveAppearance() } }
    @Published var interfaceFont = "Inter" { didSet { saveAppearance() } }
    @Published var transcriptSize = "Medium" { didSet { saveAppearance() } }
    @Published var transcriptWidth = "Narrow" { didSet { saveAppearance() } }
    @Published var transcriptView = "Normal" { didSet { saveAppearance() } }
    @Published var lightCodeTheme = CodeTheme.githubLight.rawValue { didSet { saveAppearance() } }
    @Published var darkCodeTheme = CodeTheme.githubDark.rawValue { didSet { saveAppearance() } }
    @Published var memoryEnabled = true
    @Published var memories: [String] = []
    @Published var usagePeriod: CodeUsagePeriod = .all
    @Published var scheduleComposerPrompt = ""
    @Published var scheduleComposerTime = ""
    @Published var scheduleComposerOpen = false
    @Published var turnRunning = false
    @Published var coworkInstructions = ""
    @Published var mcpConfig = "{\n  \"mcp_servers\": {}\n}"
    @Published var mcpServerLines: [String] = []
    @Published var interfaceLanguage = "English"
    @Published var changelogPresented = false
    @Published private(set) var sessions: [SessionSummary] = []
    @Published var codeTaskPreview: String?
    @Published var pendingPermission: PermissionRequestRecord?
    @Published var transcript: [StoredMessage] = []
    @Published var todos: [TodoItem] = []
    @Published var threadDraft = ""
    @Published var threadFindQuery = ""
    @Published var pendingQuestions: [(callID: String, question: String)] = []
    @Published var childTranscriptSessionID: String?

    let store: HarnessStore
    private var restoringAppearance = false
    private var toastDismissTask: Task<Void, Never>?
    private var scheduleWatch: Task<Void, Never>?
    private var prepareTask: Task<Void, Never>?
    private var awakeActivity: NSObjectProtocol?
    private(set) var runner: SessionRunner
    @Published private(set) var sessionID: String
    private var drain: (sessionID: String, task: Task<Void, Never>)?
    /// The one engine every session's runner shares.
    private var sharedTurn: any ModelTurn
    /// The folder the next new task opens in, chosen with Select folder… or a project menu.
    private(set) var nextProjectPath: String?
    let supportDirectory: URL
    /// Tests and screenshot launches may answer with the stand-in. A normal launch may not.
    let allowsScriptedReplies: Bool
    var blockScriptedRepliesForTest = false

    private init(
        store: HarnessStore,
        model: any ModelTurn,
        sessionID: String,
        supportDirectory: URL,
        allowsScriptedReplies: Bool
    ) {
        self.store = store
        self.sharedTurn = model
        self.runner = SessionRunner(sessionID: sessionID, store: store, model: model)
        self.sessionID = sessionID
        self.supportDirectory = supportDirectory
        self.allowsScriptedReplies = allowsScriptedReplies
    }

    static func makeForLaunch() throws -> AppModel {
        try make(sessionDirectory: defaultSupportDirectory(), allowsScriptedReplies: false)
    }

    static func makeForTesting(databaseURL: URL) throws -> AppModel {
        try make(sessionDirectory: databaseURL.deletingLastPathComponent(), allowsScriptedReplies: true)
    }

    private static func make(sessionDirectory: URL, allowsScriptedReplies: Bool) throws -> AppModel {
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        let dbURL = sessionDirectory.appendingPathComponent("yuzu.sqlite")
        let store = try HarnessStore(path: dbURL.path)
        let project = sessionDirectory.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let sessionID: String
        if let latest = try store.sessionSummaries().first {
            sessionID = latest.id
        } else {
            sessionID = "main"
            try store.insertSession(
                SessionRecord(
                    id: sessionID,
                    projectPath: project.path,
                    agentID: "build",
                    modelIdentifier: "pending",
                    epochID: "epoch-1",
                    stepCount: 0,
                    supportsMultipleToolCalls: true,
                    status: SessionStatus.idle,
                    modelMessageCursor: 0,
                    manualPressed: true
                )
            )
        }
        let model = ScriptedTurn(turns: [AssistantTurn(text: "")])
        return AppModel(
            store: store,
            model: model,
            sessionID: sessionID,
            supportDirectory: sessionDirectory,
            allowsScriptedReplies: allowsScriptedReplies
        )
            .restoringSavedSettings()
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
        codeThreadOpen = false
    }

    /// The handoff's Escape order: open popovers and dialogs, then Settings, the changelog,
    /// search, and last the task inspector. `false` lets the key through.
    func handleEscape() -> Bool {
        if escapeStack.closeTop() { return true }
        if settingsPresented {
            settingsPresented = false
            return true
        }
        if changelogPresented {
            changelogPresented = false
            return true
        }
        if searchOpen {
            searchOpen = false
            return true
        }
        if workspaceMode == .cowork, coworkDestination == .task, inspectorOpen {
            inspectorOpen = false
            return true
        }
        return false
    }

    struct SearchResult: Identifiable {
        let id: String
        let label: String
        let open: () -> Void
    }

    /// Pages, task titles, skill names and Settings tabs whose label contains the query; at most ten.
    func searchResults(_ query: String) -> [SearchResult] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var results: [SearchResult] = []
        for page in CoworkDestination.allCases where page != .task {
            results.append(SearchResult(id: "page-\(page.rawValue)", label: page.rawValue) { [weak self] in
                self?.selectCowork(page)
            })
        }
        results.append(SearchResult(id: "page-Code", label: "Code") { [weak self] in self?.selectCode() })
        for task in taskSessions {
            results.append(SearchResult(id: "task-\(task.id)", label: task.displayTitle) { [weak self] in
                self?.openTask(task.id)
            })
        }
        for skill in SkillCatalog.discover(projectPath: workspaceProjectPath) {
            results.append(SearchResult(id: "skill-\(skill.name)", label: skill.name) { [weak self] in
                self?.selectCowork(.customize)
                self?.requestedSkill = skill.name
            })
        }
        for tab in SettingsTab.allCases {
            results.append(SearchResult(id: "settings-\(tab.rawValue)", label: "Settings › \(tab.rawValue)") { [weak self] in
                self?.openSettings(tab: tab)
            })
        }
        return Array(results.filter { term.isEmpty || $0.label.lowercased().contains(term) }.prefix(10))
    }

    func openSettings(tab: SettingsTab = .general, anchor: SettingsAnchor? = nil) {
        settingsTab = tab
        settingsAnchor = anchor
        settingsPresented = true
    }

    var logURL: URL {
        supportDirectory.appendingPathComponent("logs", isDirectory: true).appendingPathComponent("yuzu.log")
    }

    func log(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let data = Data("\(stamp) \(line)\n".utf8)
        let url = logURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    /// Reveals the log in Finder, creating it first so there is always a file to select.
    func openLogs() {
        if !FileManager.default.fileExists(atPath: logURL.path) {
            log("log opened")
        }
        NSWorkspace.shared.activateFileViewerSelecting([logURL])
    }

    func saveWorkDescription() {
        try? workDescription.write(
            to: supportDirectory.appendingPathComponent("work-description.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    func toggleManual() async {
        permissionPosture = permissionPosture.next
        await runner.setPermissionPosture(permissionPosture)
    }

    /// `newTask` starts a fresh session (Code home, Cowork New). The thread composer continues the open one.
    func sendPrompt(_ text: String, newTask: Bool = false) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let admitted = await admitComposerCommand(trimmed)
        guard !admitted.isEmpty else { return }
        if runner.modelBacking != .uzu, !scriptedRepliesAllowed, !blockScriptedRepliesForTest {
            await prepareAdvisedModel()
        }
        guard runner.modelBacking == .uzu || scriptedRepliesAllowed else {
            showToast("Could not download a model")
            return
        }
        if newTask {
            beginTask()
            if workspaceMode == .cowork {
                selectCowork(.task)
            } else {
                codeTaskPreview = trimmed
                codeThreadOpen = true
            }
        }
        let runner = self.runner
        let target = sessionID
        if let drain, drain.sessionID != target {
            await drain.task.value
        }
        runner.requestedReasoningEffort = reasoningEffort
        let status = try? store.session(id: target)?.status
        let drainBusy = drain?.sessionID == target
        let shouldQueue = turnRunning || drainBusy || status == .running || status == .waitingPermission
        if shouldQueue {
            _ = try? store.appendInbox(sessionID: target, text: admitted, delivery: .queue)
            reloadSessions()
            Task { await runner.run() }
            return
        }
        replyFloor = transcript.count
        turnRunning = true
        defer { turnRunning = false }
        let started = Date()
        let tokensBefore = outputTokens(sessionID: target)
        _ = try? store.appendInbox(sessionID: target, text: admitted, delivery: .steer)
        reloadSessions()
        let finished = OSAllocatedUnfairLock(initialState: false)
        let runTask = Task {
            await runner.run()
            finished.withLock { $0 = true }
        }
        drain = (target, runTask)
        while !Task.isCancelled {
            reloadTranscript()
            applyLiveGeneration()
            refreshPendingPermission()
            let waiting = (try? store.pendingPermissionRequests(sessionID: target))?.isEmpty == false
            if !waiting, finished.withLock({ $0 }) {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        await runTask.value
        if drain?.sessionID == target {
            drain = nil
        }
        reloadTranscript()
        reloadSessions()
        applyLiveGeneration()
        let added = outputTokens(sessionID: target) - tokensBefore
        let elapsed = Date().timeIntervalSince(started)
        if speedLabel == "—",
           let live = runner.liveGeneration(),
           let rate = live.generateTokensPerSecond,
           rate.isFinite,
           rate > 0 {
            speedLabel = "\(Int(rate.rounded())) tok/s"
        } else if speedLabel == "—", added > 0, elapsed >= 0.5 {
            speedLabel = "\(Int((Double(added) / elapsed).rounded())) tok/s"
        }
        log("turn finished session=\(target) tokens=\(added) seconds=\(String(format: "%.1f", elapsed))")
        if workspaceMode == .cowork, sessionID == target {
            showTaskThread = true
            coworkDestination = .task
        }
        recordMemory(trimmed)
        notifyResponseFinished()
    }

    private func outputTokens(sessionID: String) -> Int {
        ((try? store.messages(sessionID: sessionID)) ?? []).reduce(0) { $0 + ($1.outputTokens ?? 0) }
    }

    func reloadSessions() {
        sessions = (try? store.sessionSummaries()) ?? []
    }

    /// Tasks for the mode that is open. Cowork and Code do not share a list.
    var taskSessions: [SessionSummary] {
        let surface: SessionSurface = workspaceMode == .code ? .code : .cowork
        return sessions.filter { session in
            session.surface == surface && (
                session.messageCount > 0
                    || session.id == sessionID && (
                        (surface == .cowork && showTaskThread && coworkDestination == .task)
                            || (surface == .code && codeThreadOpen)
                    )
            )
        }
    }

    /// Code tasks grouped by folder. A task with no chosen folder is Sandbox.
    var codeWorkspaceGroups: [(name: String, tasks: [SessionSummary])] {
        let groups = Dictionary(grouping: taskSessions, by: { workspaceLabel($0.projectPath) })
        return groups.keys.sorted { lhs, rhs in
            if lhs == "Sandbox" { return true }
            if rhs == "Sandbox" { return false }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }.map { name in
            (name, groups[name] ?? [])
        }
    }

    var pinnedSessions: [SessionSummary] {
        taskSessions.filter(\.pinned)
    }

    private var currentSummary: SessionSummary? {
        sessions.first { $0.id == sessionID }
    }

    var taskTitle: String { currentSummary?.displayTitle ?? "Task" }
    var taskPinned: Bool { currentSummary?.pinned ?? false }

    func renameCurrentTask(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        try? store.setSessionTitle(id: sessionID, title: trimmed.isEmpty ? nil : trimmed)
        reloadSessions()
    }

    func togglePinCurrentTask() {
        try? store.setSessionPinned(id: sessionID, pinned: !taskPinned)
        reloadSessions()
    }

    /// Reuses the open session when it is still empty, otherwise opens a new one.
    /// Cowork always uses Sandbox. Code uses the selected folder, or Sandbox when none is chosen.
    func beginTask() {
        let current = try? store.session(id: sessionID)
        let empty = ((try? store.messages(sessionID: sessionID)) ?? []).isEmpty
            && ((try? store.inboxRows(sessionID: sessionID)) ?? []).isEmpty
        let surface: SessionSurface = workspaceMode == .code ? .code : .cowork
        let project = taskProjectPath(for: surface)
        try? FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        if empty, var current {
            current.projectPath = project
            current.surface = surface
            try? store.updateSession(current)
            reloadSessions()
            return
        }
        let id = UUID().uuidString
        let record = SessionRecord(
            id: id,
            projectPath: project,
            surface: surface,
            agentID: "build",
            modelIdentifier: installedModelIdentifier ?? current?.modelIdentifier ?? "pending",
            epochID: UUID().uuidString,
            stepCount: 0,
            supportsMultipleToolCalls: true,
            status: .idle,
            modelMessageCursor: 0,
            permissionPosture: permissionPosture
        )
        guard (try? store.insertSession(record)) != nil else { return }
        switchSession(to: id)
    }

    /// Swaps the engine for every session in the window, the open one and any opened later.
    func useModel(_ turn: any ModelTurn) {
        sharedTurn = turn
        runner.useModel(turn)
    }

    func openTask(_ id: String) {
        if id != sessionID {
            switchSession(to: id)
        }
        let surface = sessions.first { $0.id == id }?.surface ?? .cowork
        if surface == .code {
            workspaceMode = .code
            codeThreadOpen = true
        } else {
            codeThreadOpen = false
            selectCowork(.task)
        }
    }

    private func taskProjectPath(for surface: SessionSurface) -> String {
        if surface == .cowork { return sandboxPath }
        return nextProjectPath ?? sandboxPath
    }

    func workspaceLabel(_ path: String) -> String {
        if isSandbox(path) { return "Sandbox" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    func isSandbox(_ path: String) -> Bool {
        path.isEmpty || path == sandboxPath || path == defaultWorkspacePath
    }

    func deleteCurrentTask() {
        let doomed = sessionID
        let surface = sessions.first { $0.id == doomed }?.surface ?? .cowork
        let siblings = sessions.filter { $0.id != doomed && $0.messageCount > 0 && $0.surface == surface }
        if let other = siblings.first {
            switchSession(to: other.id)
            if surface == .code { codeThreadOpen = true }
        } else {
            beginTaskReplacing(doomed)
            if surface == .code { codeThreadOpen = false }
        }
        try? store.deleteSession(id: doomed)
        reloadSessions()
        if surface == .cowork {
            selectCowork(siblings.isEmpty ? .new : .task)
        } else {
            workspaceMode = .code
        }
    }

    private func beginTaskReplacing(_ id: String) {
        let previous = try? store.session(id: id)
        let surface = previous?.surface ?? .cowork
        let project = surface == .cowork ? sandboxPath : (previous?.projectPath ?? sandboxPath)
        try? FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        let fresh = UUID().uuidString
        try? store.insertSession(
            SessionRecord(
                id: fresh, projectPath: project, surface: surface, agentID: "build",
                modelIdentifier: previous?.modelIdentifier ?? "pending",
                epochID: UUID().uuidString, stepCount: 0, supportsMultipleToolCalls: true,
                status: .idle, modelMessageCursor: 0, permissionPosture: permissionPosture
            )
        )
        switchSession(to: fresh)
    }

    private func switchSession(to id: String) {
        let next = SessionRunner(sessionID: id, store: store, model: sharedTurn)
        configure(next)
        runner = next
        sessionID = id
        if let session = try? store.session(id: id) {
            permissionPosture = session.permissionPosture
        }
        reloadTranscript()
        refreshPendingPermission()
        reloadSessions()
    }

    private var scriptedRepliesAllowed: Bool {
        if blockScriptedRepliesForTest { return false }
        return allowsScriptedReplies || ProcessInfo.processInfo.environment["YUZU_UI_ROUTE"] != nil
    }

    func testingRefuseScriptedReplies() {
        blockScriptedRepliesForTest = true
    }

    /// Task messages in the period. Subagent children count toward tokens through their parent's model.
    private func usageRows(period: CodeUsagePeriod, now: Date) -> [UsageRow] {
        let cutoff: Date?
        switch period {
        case .all: cutoff = nil
        case .days30: cutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        case .days7: cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
        }
        let rows = (try? store.usageRows()) ?? []
        return rows.filter { row in
            guard row.role == .user || row.role == .assistant else { return false }
            guard let cutoff else { return true }
            guard let at = row.at else { return false }
            return at >= cutoff
        }
    }

    func usageMetrics(period: CodeUsagePeriod, now: Date = Date()) -> UsageMetrics {
        let rows = usageRows(period: period, now: now)
        let topLevel = Set(sessions.map(\.id))
        let calendar = Calendar.current
        let dated = rows.compactMap(\.at)
        let days = Set(dated.map { calendar.startOfDay(for: $0) })
        var hourCounts: [Int: Int] = [:]
        for at in dated {
            hourCounts[calendar.component(.hour, from: at), default: 0] += 1
        }
        let peakLabel: String
        if let peak = hourCounts.max(by: { ($0.value, $1.key) < ($1.value, $0.key) })?.key {
            var parts = DateComponents()
            parts.hour = peak
            peakLabel = calendar.date(from: parts).map {
                $0.formatted(Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated)))
            } ?? "—"
        } else {
            peakLabel = "—"
        }
        return UsageMetrics(
            sessions: Set(rows.map(\.sessionID)).intersection(topLevel).count,
            messages: rows.count,
            tokens: rows.reduce(0) { $0 + ($1.outputTokens ?? 0) },
            activeDays: days.count,
            peakHour: peakLabel,
            favoriteModel: modelShares(period: period, now: now).first?.name ?? "—"
        )
    }

    /// One entry per model with output tokens, largest share first.
    func modelShares(period: CodeUsagePeriod, now: Date = Date()) -> [(name: String, share: Double)] {
        var tokens: [String: Int] = [:]
        for row in usageRows(period: period, now: now) {
            guard let count = row.outputTokens, count > 0 else { continue }
            tokens[row.modelIdentifier, default: 0] += count
        }
        let total = Double(tokens.values.reduce(0, +))
        guard total > 0 else { return [] }
        return tokens
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .map { (displayName(modelIdentifier: $0.key), Double($0.value) / total) }
    }

    /// The last 26 days, oldest first: 0 idle, 1 active, 2 at least half the busiest day's messages.
    func activityLevels(now: Date = Date()) -> [Int] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var counts: [Date: Int] = [:]
        for at in usageRows(period: .all, now: now).compactMap(\.at) {
            counts[calendar.startOfDay(for: at), default: 0] += 1
        }
        let days = (0..<26).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let busiest = days.map { counts[$0] ?? 0 }.max() ?? 0
        return days.map { day in
            let count = counts[day] ?? 0
            if count == 0 { return 0 }
            return busiest > 1 && count * 2 >= busiest ? 2 : 1
        }
    }

    func displayName(modelIdentifier: String) -> String {
        if modelIdentifier == installedModelIdentifier, let installedModelName { return installedModelName }
        let parts = modelIdentifier.split(separator: ":").map(String.init)
        guard parts.count >= 3 else { return modelIdentifier }
        return "\(parts[1].prefix(1).uppercased())\(parts[1].dropFirst()) \(parts[2].uppercased())"
    }

    var allTimeTokenCount: Int {
        ((try? store.usageRows()) ?? []).reduce(0) { $0 + ($1.outputTokens ?? 0) }
    }

    func stopTurn() async {
        await runner.cancel()
        refreshPendingPermission()
    }

    /// `/name` from a slash skill or a connected MCP prompt becomes the admitted text.
    func admitComposerCommand(_ text: String) async -> String {
        let skills = SkillCatalog.discover(projectPath: workspaceProjectPath)
        if let expanded = ComposerCommands.skillExpansion(text: text, skills: skills) {
            return expanded
        }
        guard let command = ComposerCommands.command(text) else { return text }
        if command.name == "schedule" {
            let tail = command.tail
            if !tail.isEmpty, ScheduleClock.nextRun(scheduleText: tail, now: Date()) != nil {
                scheduleComposerTime = tail
                scheduleComposerPrompt = ""
            } else {
                scheduleComposerPrompt = tail
                scheduleComposerTime = ""
            }
            scheduleComposerOpen = true
            selectCowork(.scheduled)
            return ""
        }
        guard let server = MCPHub.shared.serverName(forPrompt: command.name) else { return text }
        guard let body = try? await MCPHub.shared.getPromptText(serverName: server, name: command.name) else {
            return text
        }
        if command.tail.isEmpty { return body }
        return body + "\n\n" + command.tail
    }

    func beginMCPSignIn(serverName: String) {
        guard let uri = MCPHub.shared.authorizationURI(serverName: serverName),
              let url = URL(string: uri) else {
            showToast("This server did not provide a sign-in address.")
            return
        }
        let verifier = OAuthPKCE.verifier()
        let challenge = OAuthPKCE.challenge(for: verifier)
        Task {
            do {
                let session = try LoopbackOAuth.start()
                let openURL = Self.authorizationURL(url, redirectURI: session.redirectURI, challenge: challenge)
                NSWorkspace.shared.open(openURL)
                let code = try await session.code()
                guard let tokenURI = MCPHub.shared.tokenURI(serverName: serverName) else {
                    showToast("Sign-in returned. This server did not provide a token address.")
                    return
                }
                let token = try await OAuthTokenExchange.accessToken(
                    tokenURI: tokenURI,
                    code: code,
                    redirectURI: session.redirectURI,
                    codeVerifier: verifier
                )
                try KeychainTokenStore.save(token, account: serverName)
                guard let pending = MCPHub.shared.pendingConfig(serverName: serverName) else {
                    showToast("Signed in, but the server configuration was lost.")
                    return
                }
                try await MCPHub.shared.connect(
                    config: pending.addingBearerToken(token),
                    projectPath: workspaceProjectPath
                )
                refreshMCPLines()
                showToast("Signed in.")
            } catch {
                showToast("Could not finish sign-in.")
            }
        }
    }

    private static func authorizationURL(_ url: URL, redirectURI: String, challenge: String) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = components.queryItems ?? []
        func add(_ name: String, _ value: String) {
            guard !items.contains(where: { $0.name == name }) else { return }
            items.append(URLQueryItem(name: name, value: value))
        }
        add("response_type", "code")
        add("client_id", "yuzu")
        add("redirect_uri", redirectURI)
        add("code_challenge", challenge)
        add("code_challenge_method", "S256")
        components.queryItems = items
        return components.url ?? url
    }

    func setMemoryEnabled(_ enabled: Bool) {
        memoryEnabled = enabled
        let url = supportDirectory.appendingPathComponent("memory-enabled.txt")
        try? (enabled ? "1" : "0").write(to: url, atomically: true, encoding: .utf8)
    }

    func recordMemory(_ text: String) {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard memoryEnabled, !line.isEmpty else { return }
        var items = memories
        guard !items.contains(line) else { return }
        items.append(line)
        memories = items
        let body = items.joined(separator: "\n")
        try? body.write(to: supportDirectory.appendingPathComponent("memories.md"), atomically: true, encoding: .utf8)
    }

    /// Steps for the Progress bar. The model's own list wins. Otherwise the steps are the tools from the latest turn.
    var taskSteps: [TaskStep] {
        if !todos.isEmpty {
            return todos.enumerated().map { index, item in
                TaskStep(id: "todo-\(index)", title: item.content, status: item.status)
            }
        }
        return toolStepsSinceLastUser
    }

    var taskProgressFraction: Double {
        let steps = taskSteps
        if steps.isEmpty { return turnRunning ? 0.12 : 0 }
        let done = steps.filter { $0.status == .completed }.count
        let partial = steps.contains { $0.status == .inProgress } ? 0.45 : 0
        return min(1, (Double(done) + partial) / Double(steps.count))
    }

    var taskProgressLabel: String {
        let steps = taskSteps
        if steps.isEmpty { return turnRunning ? "Working" : "No steps yet" }
        let done = steps.filter { $0.status == .completed }.count
        if let current = steps.first(where: { $0.status == .inProgress }) {
            return "\(done) of \(steps.count) · \(current.title)"
        }
        return "\(done) of \(steps.count) steps"
    }

    private var toolStepsSinceLastUser: [TaskStep] {
        guard let start = transcript.lastIndex(where: { $0.role == .user }) else {
            return turnRunning ? [TaskStep(id: "working", title: "Working", status: .inProgress)] : []
        }
        let finished = Set(transcript[start...].filter { $0.role == .tool }.compactMap(\.toolCallID))
        var steps: [TaskStep] = []
        for message in transcript[start...] where message.role == .assistant {
            for call in message.toolCalls {
                let status: TodoItem.Status
                if finished.contains(call.id) {
                    status = .completed
                } else if turnRunning {
                    status = .inProgress
                } else {
                    status = .pending
                }
                steps.append(TaskStep(id: call.id, title: taskStepTitle(call), status: status))
            }
        }
        if steps.isEmpty, turnRunning {
            steps.append(TaskStep(id: "working", title: "Working", status: .inProgress))
        }
        return steps
    }

    private func taskStepTitle(_ call: ToolCall) -> String {
        let verb: String
        switch call.name {
        case "read": verb = "Read"
        case "write": verb = "Write"
        case "edit": verb = "Edit"
        case "bash": verb = "Shell"
        case "grep": verb = "Search"
        case "glob": verb = "Find"
        case "webfetch": verb = "Fetch"
        case "todowrite": verb = "Plan"
        case "skill": verb = "Skill"
        case "task": verb = "Task"
        default: verb = call.name
        }
        guard case .object(let fields) = call.arguments else { return verb }
        if case .string(let path)? = fields["path"], !path.isEmpty {
            return "\(verb) \(URL(fileURLWithPath: path).lastPathComponent)"
        }
        if case .string(let command)? = fields["command"], !command.isEmpty {
            let first = command.split(whereSeparator: \.isNewline).first.map(String.init) ?? command
            let clipped = first.count > 36 ? String(first.prefix(35)) + "…" : first
            return "Shell \(clipped)"
        }
        if case .string(let query)? = fields["pattern"] ?? fields["query"], !query.isEmpty {
            let clipped = query.count > 28 ? String(query.prefix(27)) + "…" : query
            return "\(verb) \(clipped)"
        }
        return verb
    }

    func reloadTranscript() {
        let messages = (try? store.messages(sessionID: sessionID)) ?? []
        if messages != transcript { transcript = messages }
        let mcpURL = supportDirectory.appendingPathComponent("mcp.json")
        if let saved = try? String(contentsOf: mcpURL, encoding: .utf8), saved != mcpConfig {
            mcpConfig = saved
            refreshMCPLines()
        }
        let steps = (try? store.todos(sessionID: sessionID)) ?? []
        if steps != todos { todos = steps }
        refreshPendingQuestions()
    }

    func refreshPendingQuestions() {
        Task {
            let list = await QuestionTool.Broker.shared.pendingQuestions(sessionID: sessionID)
            await MainActor.run {
                pendingQuestions = list
            }
        }
    }

    func answerPendingQuestion(callID: String, answer: String) async {
        await QuestionTool.Broker.shared.answer(sessionID: sessionID, callID: callID, text: answer)
        reloadTranscript()
        await runner.run()
    }

    func revertLastTurn() async {
        _ = await runner.revertLastUserTurn()
        reloadTranscript()
        reloadSessions()
    }

    func setSessionAgent(_ agentID: String) async {
        await runner.setAgent(agentID)
        reloadSessions()
    }

    var sessionAgentID: String {
        (try? store.session(id: sessionID)?.agentID) ?? "build"
    }

    var awaitingAssistantText: Bool {
        guard turnRunning else { return false }
        let start = min(replyFloor, transcript.count)
        let assistant = transcript.dropFirst(start).last { $0.role == .assistant }
        let text = assistant?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let reasoning = assistant?.reasoning.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty && reasoning.isEmpty
    }

    private func applyLiveGeneration() {
        guard let live = runner.liveGeneration() else { return }
        // Decode rate: (generated tokens − 1) / time since the first token.
        // Prefill is not in the denominator. Reasoning tokens are part of the generated count.
        if let rate = live.generateTokensPerSecond, rate.isFinite, rate > 0 {
            speedLabel = "\(Int(rate.rounded())) tok/s"
        }
        guard live.totalTokens > 0 else { return }
        guard let session = try? store.session(id: sessionID), session.contextLength > 0 else { return }
        let pct = min(100, Int((Double(live.totalTokens) / Double(session.contextLength) * 100).rounded()))
        liveContextLabel = "\(live.totalTokens.formatted()) (\(pct)%)"
    }

    var threadHarnessEvents: [HarnessEventRecord] {
        (try? store.harnessEvents(sessionID: sessionID)) ?? []
    }

    var threadContextUsageLabel: String {
        if let liveContextLabel { return liveContextLabel }
        guard let session = try? store.session(id: sessionID), session.contextLength > 0 else { return "—" }
        let projected = (try? runner.contextCoordinator.projectedHistory(
            store: store,
            sessionID: sessionID,
            session: session
        )) ?? []
        let baseline = try? runner.contextCoordinator.baselineSystemText(
            store: store,
            sessionID: sessionID,
            epochID: session.epochID
        )
        let used = Compaction.estimateTokens(messages: projected, baseline: baseline)
        let pct = Int((Double(used) / Double(session.contextLength) * 100).rounded())
        return "\(used.formatted()) (\(pct)%)"
    }

    struct FileReviewRow: Identifiable, Equatable {
        let id: String
        let path: String
        let kind: String
        let preview: String
    }

    var fileReviewRows: [FileReviewRow] {
        var rows: [FileReviewRow] = []
        for message in transcript where message.role == .assistant {
            for call in message.toolCalls where call.name == "write" || call.name == "edit" {
                guard case .object(let fields) = call.arguments,
                      case .string(let path)? = fields["path"], !path.isEmpty else { continue }
                let preview: String
                if call.name == "edit" {
                    let old = Self.argumentString(call.arguments, key: "old_string")
                    let new = Self.argumentString(call.arguments, key: "new_string")
                    preview = "-\(old)\n+\(new)"
                } else {
                    preview = Self.argumentString(call.arguments, key: "body")
                }
                rows.append(FileReviewRow(
                    id: call.id,
                    path: path,
                    kind: call.name == "write" ? "write" : "edit",
                    preview: String(preview.prefix(800))
                ))
            }
        }
        return rows
    }

    func childSessionID(forTaskCall callID: String) -> String? {
        try? store.taskChildSessionID(parentSessionID: sessionID, toolCallID: callID)
    }

    private static func argumentString(_ value: JSONValue, key: String) -> String {
        guard case .object(let fields) = value, case .string(let text)? = fields[key] else { return "" }
        return text
    }

    func installMCPServer(name: String, command: String, args: [String]) {
        let file = supportDirectory.appendingPathComponent("mcp.json")
        guard let text = try? MCPTool.install(
            name: name.isEmpty ? "duckduckgo" : name,
            command: command.isEmpty ? nil : command,
            args: args,
            url: nil,
            at: file
        ) else { return }
        mcpConfig = text
        refreshMCPLines()
        Task { await applySavedMCPConfig() }
    }

    func removeMCPServer(named name: String) {
        guard var entries = try? MCPConfig.parse(mcpConfig) else { return }
        entries.removeAll { $0.name == name }
        mcpConfig = MCPConfig.encode(entries)
        saveMCPConfig()
    }

    func setMCPServerEnabled(_ name: String, enabled: Bool) {
        guard var entries = try? MCPConfig.parse(mcpConfig) else { return }
        guard let index = entries.firstIndex(where: { $0.name == name }) else { return }
        entries[index].enabled = enabled
        mcpConfig = MCPConfig.encode(entries)
        saveMCPConfig()
    }

    func connectMCPServer(named name: String) async {
        guard let entry = (try? MCPConfig.parse(mcpConfig))?.first(where: { $0.name == name }) else { return }
        try? await runner.mcpConnect(entry.config)
        refreshMCPLines()
    }

    func disconnectMCPServer(named name: String) {
        runner.mcpDisconnect(name)
        refreshMCPLines()
    }

    /// Files the model read, wrote or edited in this task, in first-use order.
    var referencedFiles: [String] {
        var seen = Set<String>()
        var files: [String] = []
        for message in transcript where message.role == .assistant {
            for call in message.toolCalls where ["read", "write", "edit"].contains(call.name) {
                guard case .object(let fields) = call.arguments,
                      case .string(let path)? = fields["path"], !path.isEmpty else { continue }
                if seen.insert(path).inserted { files.append(path) }
            }
        }
        return files
    }

    func resolvedProjectURL(_ path: String) -> URL {
        path.hasPrefix("/") ? URL(fileURLWithPath: path)
            : URL(fileURLWithPath: workspaceProjectPath).appendingPathComponent(path)
    }

    func pumpTranscript() async {
        while !Task.isCancelled {
            reloadTranscript()
            refreshPendingPermission()
            let status = try? store.session(id: sessionID)?.status
            if pendingPermission == nil, status == nil || status == .idle {
                break
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        reloadTranscript()
        refreshPendingPermission()
    }

    func refreshPendingPermission() {
        pendingPermission = (try? store.pendingPermissionRequests(sessionID: sessionID))?.first
    }

    func replyToPending(_ reply: PermissionReply) async {
        guard let pending = pendingPermission else { return }
        pendingPermission = nil
        await runner.replyPermission(pending.id, reply)
    }

    /// The folder for the next new task. An open session that has no messages yet moves there too.
    func setProjectFolder(_ url: URL) {
        codeFolderName = url.lastPathComponent
        coworkProjectName = url.lastPathComponent
        nextProjectPath = url.path
        guard var session = try? store.session(id: sessionID),
              ((try? store.messages(sessionID: sessionID)) ?? []).isEmpty else { return }
        session.projectPath = url.path
        try? store.updateSession(session)
    }

    func clearProjectFolder() {
        codeFolderName = "Sandbox"
        coworkProjectName = "No project"
        nextProjectPath = nil
    }

    func submitThread() async {
        let text = threadDraft
        threadDraft = ""
        await sendPrompt(text)
    }

    func showToast(_ message: String) {
        toastMessage = message
        toastDismissTask?.cancel()
        toastDismissTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            toastMessage = nil
        }
    }

    @discardableResult
    func submitCoworkHomeTask(_ text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showToast("Write a task to get started.")
            return false
        }
        await sendPrompt(trimmed, newTask: true)
        return true
    }

    func permissionEffect(manualPressed: Bool) -> PermissionEffect {
        permissionEffect(for: PermissionPosture(manualPressed: manualPressed), action: "edit")
    }

    func permissionEffect(for posture: PermissionPosture, action: String = "edit") -> PermissionEffect {
        PermissionEvaluator.effect(
            agentID: "build",
            action: action,
            resource: "*",
            savedAllows: [],
            manualPressed: posture == .workspaceRead,
            posture: posture
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

    var hasProjects: Bool { !knownProjectFolders.isEmpty }
    var createdArtifactPaths: [String] {
        var seen = Set<String>()
        return transcript.compactMap { message in
            guard message.role == .tool, message.text.hasPrefix("Wrote ") else { return nil }
            let path = String(message.text.dropFirst("Wrote ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty, seen.insert(path).inserted else { return nil }
            return path
        }
    }
    var hasArtifacts: Bool { !allArtifacts.isEmpty }

    /// Every file a task wrote, newest task first, with the task that wrote it.
    var allArtifacts: [(path: String, taskID: String, taskTitle: String)] {
        var seen = Set<String>()
        var list: [(path: String, taskID: String, taskTitle: String)] = []
        for task in sessions where task.messageCount > 0 {
            let messages = (try? store.messages(sessionID: task.id)) ?? []
            for message in messages where message.role == .tool && message.text.hasPrefix("Wrote ") {
                let path = String(message.text.dropFirst("Wrote ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !path.isEmpty, seen.insert(path).inserted else { continue }
                list.append((path, task.id, task.displayTitle))
            }
        }
        return list
    }
    var hasPinnedItems: Bool { !pinnedSessions.isEmpty }
    var referencedToolNames: [String] {
        var names: [String] = []
        for message in transcript {
            if let name = message.toolName, !names.contains(name) {
                names.append(name)
            }
            for call in message.toolCalls where !names.contains(call.name) {
                names.append(call.name)
            }
        }
        return names
    }

    func restoringSavedSettings() -> AppModel {
        let instructionsURL = supportDirectory.appendingPathComponent("instructions.md")
        let coworkURL = supportDirectory.appendingPathComponent("cowork-instructions.md")
        let mcpURL = supportDirectory.appendingPathComponent("mcp.json")
        if let text = try? String(contentsOf: instructionsURL, encoding: .utf8) {
            yuzuInstructions = text
        }
        if let text = try? String(contentsOf: coworkURL, encoding: .utf8) {
            coworkInstructions = text
        }
        if let text = try? String(contentsOf: mcpURL, encoding: .utf8), !text.isEmpty {
            mcpConfig = text
        }
        if let flag = try? String(contentsOf: supportDirectory.appendingPathComponent("memory-enabled.txt"), encoding: .utf8) {
            memoryEnabled = flag.trimmingCharacters(in: .whitespacesAndNewlines) != "0"
        }
        if let saved = try? String(contentsOf: supportDirectory.appendingPathComponent("memories.md"), encoding: .utf8) {
            memories = saved.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        }
        if let saved = try? String(contentsOf: supportDirectory.appendingPathComponent("work-description.txt"), encoding: .utf8),
           !saved.isEmpty {
            workDescription = saved
        }
        restoreAppearance()
        configure(runner)
        reloadSessions()
        refreshMCPLines()
        return self
    }

    private func configure(_ runner: SessionRunner) {
        let directory = supportDirectory
        runner.mcpConfigURL = directory.appendingPathComponent("mcp.json")
        runner.contextCoordinator.loadUserInstructions = {
            var parts = ["instructions.md", "cowork-instructions.md"].compactMap { name -> String? in
                let url = directory.appendingPathComponent(name)
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            if let work = try? String(contentsOf: directory.appendingPathComponent("work-description.txt"), encoding: .utf8),
               work != "Select", !work.isEmpty {
                parts.insert("The user's work: \(work).", at: 0)
            }
            let enabled = (try? String(contentsOf: directory.appendingPathComponent("memory-enabled.txt"), encoding: .utf8))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } != "0"
            if enabled,
               let memories = try? String(contentsOf: directory.appendingPathComponent("memories.md"), encoding: .utf8),
               !memories.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(memories.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
        }
    }

    func saveInstructions() {
        let instructionsURL = supportDirectory.appendingPathComponent("instructions.md")
        let coworkURL = supportDirectory.appendingPathComponent("cowork-instructions.md")
        try? yuzuInstructions.write(to: instructionsURL, atomically: true, encoding: .utf8)
        try? coworkInstructions.write(to: coworkURL, atomically: true, encoding: .utf8)
    }

    func saveMCPConfig() {
        let url = supportDirectory.appendingPathComponent("mcp.json")
        try? mcpConfig.write(to: url, atomically: true, encoding: .utf8)
        refreshMCPLines()
        Task { await applySavedMCPConfig() }
    }

    /// Connects enabled servers from the saved document. Disabled entries stay listed and are not connected.
    func applySavedMCPConfig() async {
        if ProcessInfo.processInfo.environment["YUZU_UI_ROUTE"] != nil { return }
        let url = supportDirectory.appendingPathComponent("mcp.json")
        guard FileManager.default.fileExists(atPath: url.path),
              let json = try? String(contentsOf: url, encoding: .utf8)
        else {
            refreshMCPLines()
            return
        }
        if mcpConfig != json {
            mcpConfig = json
        }
        guard let entries = try? MCPConfig.parse(json) else {
            refreshMCPLines()
            return
        }
        let enabled = Set(entries.filter(\.enabled).map(\.name))
        for name in MCPHub.shared.connectedServerNames() where !enabled.contains(name) {
            MCPHub.shared.disconnect(serverName: name)
        }
        for entry in entries where entry.enabled {
            if MCPHub.shared.status(serverName: entry.name) == .connected { continue }
            try? await MCPHub.shared.connect(config: entry.config, projectPath: workspaceProjectPath)
        }
        refreshMCPLines()
    }

    func refreshMCPLines() {
        guard let entries = try? MCPConfig.parse(mcpConfig) else {
            mcpServerLines = []
            return
        }
        mcpServerLines = entries.map { entry in
            let state: String
            if !entry.enabled {
                state = "disabled"
            } else {
                switch MCPHub.shared.status(serverName: entry.name) {
                case .connected: state = "connected"
                case .needsAuth: state = "needs auth"
                case .failed(let message): state = message
                case nil: state = "not connected"
                }
            }
            return "\(entry.name) · \(state)"
        }
    }

    private var appearanceURL: URL {
        supportDirectory.appendingPathComponent("appearance.json")
    }

    private func restoreAppearance() {
        guard let data = try? Data(contentsOf: appearanceURL),
              let saved = try? JSONDecoder().decode(AppearanceSettings.self, from: data) else { return }
        restoringAppearance = true
        defer { restoringAppearance = false }
        if let value = AppTheme(rawValue: saved.theme) { theme = value }
        chatFont = YuzuFonts.chatChoices.contains(saved.chatFont) ? saved.chatFont : "Source Serif"
        motionSetting = saved.motionSetting
        codeFont = saved.codeFont
        interfaceFont = YuzuFonts.interfaceChoices.contains(saved.interfaceFont) ? saved.interfaceFont : "Inter"
        transcriptSize = saved.transcriptSize
        transcriptWidth = saved.transcriptWidth
        transcriptView = saved.transcriptView
        lightCodeTheme = saved.lightCodeTheme
        darkCodeTheme = saved.darkCodeTheme
    }

    private func saveAppearance() {
        guard !restoringAppearance else { return }
        let settings = AppearanceSettings(
            theme: theme.rawValue,
            chatFont: chatFont,
            motionSetting: motionSetting,
            codeFont: codeFont,
            interfaceFont: interfaceFont,
            transcriptSize: transcriptSize,
            transcriptWidth: transcriptWidth,
            transcriptView: transcriptView,
            lightCodeTheme: lightCodeTheme,
            darkCodeTheme: darkCodeTheme
        )
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: appearanceURL, options: .atomic)
    }

    var isDarkAppearance: Bool {
        theme.palette.canvas == Tokens.dark.canvas
    }

    /// The code theme for the window's current light or dark appearance.
    func activeCodeTheme(dark: Bool) -> CodeTheme {
        let raw = dark ? darkCodeTheme : lightCodeTheme
        return CodeTheme(rawValue: raw) ?? (dark ? .githubDark : .githubLight)
    }

    var transcriptFontSize: CGFloat {
        switch transcriptSize {
        case "Small": return 14
        case "Large": return 18
        default: return 16
        }
    }

    var transcriptColumnMax: CGFloat {
        switch transcriptWidth {
        case "Medium": return 960
        case "Wide": return 1100
        default: return CGFloat(Tokens.contentWidth)
        }
    }

    var loadedContextLength: Int {
        (try? store.session(id: sessionID)?.contextLength) ?? CompactionSettings.production.contextLength
    }

    var storeFilePath: String {
        supportDirectory.appendingPathComponent("yuzu.sqlite").path
    }

    func trustedFolderPaths() -> [String] {
        let rules = (try? store.permissionRules(projectPath: workspaceProjectPath)) ?? []
        return rules.compactMap { rule in
            guard rule.effect == .allow, rule.resource.hasSuffix("/*") else { return nil }
            return String(rule.resource.dropLast(2))
        }
    }

    func allowTrustedFolder(_ path: String) {
        let folder = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard !folder.isEmpty else { return }
        try? store.insertPermissionRule(
            projectPath: workspaceProjectPath,
            rule: PermissionRule(action: "*", resource: folder + "/*", effect: .allow)
        )
    }

    func setResponseCompletions(_ enabled: Bool) {
        responseCompletions = enabled
        guard enabled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyResponseFinished() {
        guard responseCompletions else { return }
        let content = UNMutableNotificationContent()
        content.title = "Yuzu"
        content.body = "Response finished."
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func exportSessionJSON() throws -> Data {
        try JSONEncoder().encode(store.exportSessionDocuments())
    }

    func importSessionJSON(_ data: Data) throws {
        let documents = try JSONDecoder().decode([SessionDocument].self, from: data)
        try store.importSessionDocuments(documents)
        reloadTranscript()
        reloadSessions()
    }

    var modelDisplayName: String {
        if let downloadStatus { return downloadStatus }
        if let installedModelName, !installedModelName.isEmpty { return installedModelName }
        return "Download model"
    }

    /// True while no model is loaded. The picker then downloads one instead of opening its menu.
    var needsModelDownload: Bool {
        runner.modelBacking != .uzu
            && !scriptedRepliesAllowed
            && ProcessInfo.processInfo.environment["YUZU_UI_ROUTE"] == nil
    }

    /// Starts (or retries) the advised model download. Progress shows in the picker label.
    func downloadModel() {
        guard needsModelDownload, prepareTask == nil else { return }
        Task { await prepareAdvisedModel() }
    }

    func reloadSchedules() {
        scheduledTasks = (try? store.scheduledTasks()) ?? []
        syncAwakeActivity()
    }

    func createScheduledTask(name: String, prompt: String, scheduleText: String) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSchedule = scheduleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedPrompt.isEmpty, !trimmedSchedule.isEmpty else {
            throw ScheduleError.emptyField
        }
        guard let nextRun = ScheduleClock.nextRun(scheduleText: trimmedSchedule, now: Date()) else {
            throw ScheduleError.unrecognizedSchedule
        }
        try store.insertScheduledTask(
            ScheduledTaskRecord(
                id: UUID().uuidString,
                name: trimmedName,
                prompt: trimmedPrompt,
                scheduleText: trimmedSchedule,
                nextRun: nextRun
            )
        )
        reloadSchedules()
    }

    func setKeepAwake(_ enabled: Bool) {
        keepAwake = enabled
        syncAwakeActivity()
    }

    func startScheduleWatch() {
        if ProcessInfo.processInfo.environment["YUZU_UI_ROUTE"] != nil { return }
        reloadSchedules()
        guard scheduleWatch == nil else { return }
        scheduleWatch = Task { @MainActor in
            while !Task.isCancelled {
                await fireDueSchedules()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func fireDueSchedules(now: Date = Date()) async {
        let due = scheduledTasks.filter { $0.nextRun <= now }
        guard !due.isEmpty else { return }
        for task in due {
            await sendPrompt(task.prompt)
            if let next = ScheduleClock.nextRun(scheduleText: task.scheduleText, now: Date()) {
                try? store.updateScheduledTaskNextRun(id: task.id, nextRun: next)
            }
        }
        reloadSchedules()
    }

    private func syncAwakeActivity() {
        let armed = keepAwake && !scheduledTasks.isEmpty
        if armed, awakeActivity == nil {
            awakeActivity = ProcessInfo.processInfo.beginActivity(
                options: .idleSystemSleepDisabled,
                reason: "Yuzu scheduled tasks"
            )
        } else if !armed, let token = awakeActivity {
            ProcessInfo.processInfo.endActivity(token)
            awakeActivity = nil
        }
    }

    /// Downloads the chat model uzu ranks as the best fit for this Mac's total memory.
    /// Weights go to uzu's cache. The app bundle stays empty of them.
    /// UI capture launches set `YUZU_UI_ROUTE` and stay on the scripted stand-in.
    func prepareAdvisedModel() async {
        if ProcessInfo.processInfo.environment["YUZU_UI_ROUTE"] != nil { return }
        if runner.modelBacking == .uzu { return }
        if let prepareTask {
            await prepareTask.value
            return
        }
        let task = Task { @MainActor in
            await self.installAdvisedModel()
        }
        prepareTask = task
        await task.value
    }

    private func installAdvisedModel() async {
        downloadStatus = "Asking uzu which model fits this Mac…"
        do {
            let installed = try await UzuRuntime.installAdvised { status in
                self.downloadStatus = status
            }
            sharedTurn = installed.turn
            runner.useModel(installed.turn)
            installedModelName = installed.name
            installedModelIdentifier = installed.identifier
            if var session = try store.session(id: sessionID) {
                session.modelIdentifier = installed.identifier
                try store.updateSession(session)
            }
            downloadStatus = nil
            log("model loaded \(installed.identifier)")
        } catch {
            downloadStatus = nil
            prepareTask = nil
            showToast("Could not download a model. Click the model to try again.")
            log("model install failed: \(error)")
        }
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
        case .settingsGeneral:
            openSettings(tab: .general)
        }
    }

    func applyLaunchRouteIfNeeded() {
        if let themeRaw = ProcessInfo.processInfo.environment["YUZU_UI_THEME"] {
            switch themeRaw.lowercased() {
            case "light": theme = .light
            case "dark": theme = .dark
            default: break
            }
        }
        guard let raw = ProcessInfo.processInfo.environment["YUZU_UI_ROUTE"] else { return }
        guard let route = UITestRoute(launchName: raw) else { return }
        applyTestRoute(route)
    }

    var workspaceProjectPath: String {
        (try? store.session(id: sessionID)?.projectPath) ?? ""
    }

    var defaultWorkspacePath: String {
        supportDirectory.appendingPathComponent("workspace", isDirectory: true).path
    }

    /// Working directory for Cowork, and for Code tasks that have no folder yet.
    var sandboxPath: String {
        supportDirectory.appendingPathComponent("Sandbox", isDirectory: true).path
    }

    /// Folders that tasks ran in, newest first, without the app's own scratch workspace.
    var knownProjectFolders: [URL] {
        var seen = Set<String>()
        let paths = ([nextProjectPath].compactMap { $0 } + sessions.map(\.projectPath))
        return paths.compactMap { path in
            guard !isSandbox(path), seen.insert(path).inserted else { return nil }
            return URL(fileURLWithPath: path)
        }
    }

    var coworkEffortLabel: String {
        switch reasoningEffort {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high, .xHigh, .default, .disabled: return "High"
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
    case settingsGeneral

    init?(launchName: String) {
        switch launchName {
        case "code": self = .code
        case "coworkNew": self = .coworkNew
        case "coworkProjects": self = .coworkProjects
        case "coworkArtifacts": self = .coworkArtifacts
        case "coworkScheduled": self = .coworkScheduled
        case "coworkCustomize": self = .coworkCustomize
        case "coworkTask": self = .coworkTask
        case "settingsCode": self = .settingsCode
        case "settingsGeneral": self = .settingsGeneral
        default: return nil
        }
    }
}
