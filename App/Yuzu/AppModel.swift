import Foundation
import os
import AppKit
import SwiftUI
import UserNotifications
import YuzuHarness
import YuzuModel

struct UsageSample: Codable, Equatable, Sendable {
    var at: Date
    var modelName: String
}

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
    case plugins = "Plugins"
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
    @Published var reasoningEffort: ReasoningEffort = .high
    @Published var coworkProjectName = "No project"
    @Published var toastMessage: String?
    @Published var downloadStatus: String?
    @Published var sidebarSearchOpen = false
    @Published var sidebarSearch = ""
    @Published var coworkSeed: String?
    @Published var installedModelName: String?
    @Published var speedLabel = "—"
    @Published var scheduledTasks: [ScheduledTaskRecord] = []
    @Published var workDescription = "Select"
    @Published var yuzuInstructions = ""
    @Published var chatFont = "Serif"
    @Published var motionSetting = "System"
    @Published var responseCompletions = false
    @Published var codeFont = ""
    @Published var interfaceFont = "System"
    @Published var transcriptSize = "Medium"
    @Published var transcriptWidth = "Narrow"
    @Published var transcriptView = "Normal"
    @Published var memoryEnabled = true
    @Published var memories: [String] = []
    @Published var usageSamples: [UsageSample] = []
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
    @Published var taskTitle = "Task"
    @Published var taskPinned = false
    @Published var pendingPermission: PermissionRequestRecord?
    @Published var transcript: [StoredMessage] = []
    @Published var threadDraft = ""

    let store: HarnessStore
    private var toastDismissTask: Task<Void, Never>?
    private var scheduleWatch: Task<Void, Never>?
    private var prepareTask: Task<Void, Never>?
    private var awakeActivity: NSObjectProtocol?
    let runner: SessionRunner
    let sessionID: String
    let supportDirectory: URL
    /// Tests and screenshot launches may answer with the stand-in. A normal launch may not.
    let allowsScriptedReplies: Bool
    var blockScriptedRepliesForTest = false

    private init(
        store: HarnessStore,
        runner: SessionRunner,
        sessionID: String,
        supportDirectory: URL,
        allowsScriptedReplies: Bool
    ) {
        self.store = store
        self.runner = runner
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
        let sessionID = "main"
        let project = sessionDirectory.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let session = SessionRecord(
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
        if try store.session(id: sessionID) == nil {
            try store.insertSession(session)
        }
        let model = ScriptedTurn(turns: [AssistantTurn(text: "")])
        let runner = SessionRunner(sessionID: sessionID, store: store, model: model)
        return AppModel(
            store: store,
            runner: runner,
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
        let admitted = await admitComposerCommand(trimmed)
        guard !admitted.isEmpty else { return }
        if runner.modelBacking != .uzu, !scriptedRepliesAllowed, !blockScriptedRepliesForTest {
            await prepareAdvisedModel()
        }
        guard runner.modelBacking == .uzu || scriptedRepliesAllowed else {
            showToast("Could not download a model")
            return
        }
        runner.requestedReasoningEffort = reasoningEffort
        turnRunning = true
        defer { turnRunning = false }
        let started = Date()
        let tokensBefore = totalTokenCount
        _ = try? store.appendInbox(sessionID: sessionID, text: admitted, delivery: .steer)
        let finished = OSAllocatedUnfairLock(initialState: false)
        let runTask = Task {
            await runner.run()
            finished.withLock { $0 = true }
        }
        while !Task.isCancelled {
            reloadTranscript()
            refreshPendingPermission()
            let done = finished.withLock { $0 }
            if pendingPermission == nil, done {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        await runTask.value
        reloadTranscript()
        let added = totalTokenCount - tokensBefore
        let elapsed = Date().timeIntervalSince(started)
        if added > 0, elapsed >= 0.5 {
            speedLabel = "\(Int((Double(added) / elapsed).rounded())) tok/s"
        }
        if workspaceMode == .cowork {
            showTaskThread = true
            coworkDestination = .task
        }
        recordMemory(trimmed)
        noteUsage()
        notifyResponseFinished()
    }

    private var scriptedRepliesAllowed: Bool {
        if blockScriptedRepliesForTest { return false }
        return allowsScriptedReplies || ProcessInfo.processInfo.environment["YUZU_UI_ROUTE"] != nil
    }

    func testingRefuseScriptedReplies() {
        blockScriptedRepliesForTest = true
    }

    func noteUsage() {
        usageSamples.append(UsageSample(at: Date(), modelName: installedModelName ?? "local"))
        let url = supportDirectory.appendingPathComponent("usage.json")
        if let data = try? JSONEncoder().encode(usageSamples) {
            try? data.write(to: url)
        }
    }

    func usageMetrics(period: CodeUsagePeriod, now: Date = Date()) -> UsageMetrics {
        let cutoff: Date?
        switch period {
        case .all: cutoff = nil
        case .days30: cutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        case .days7: cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
        }
        let samples = usageSamples.filter { sample in
            guard let cutoff else { return true }
            return sample.at >= cutoff
        }
        let calendar = Calendar.current
        let days = Set(samples.map { calendar.startOfDay(for: $0.at) })
        var hourCounts: [Int: Int] = [:]
        for sample in samples {
            let hour = calendar.component(.hour, from: sample.at)
            hourCounts[hour, default: 0] += 1
        }
        let peak = hourCounts.max { $0.value < $1.value }?.key
        var modelCounts: [String: Int] = [:]
        for sample in samples {
            modelCounts[sample.modelName, default: 0] += 1
        }
        let favorite = modelCounts.max { $0.value < $1.value }?.key
        let peakLabel: String
        if let peak {
            var parts = DateComponents()
            parts.hour = peak
            let formatted = calendar.date(from: parts).map {
                $0.formatted(Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated)))
            }
            peakLabel = formatted ?? "—"
        } else {
            peakLabel = "—"
        }
        return UsageMetrics(
            sessions: samples.isEmpty ? (messageCount > 0 && period == .all ? 1 : 0) : 1,
            messages: period == .all ? messageCount : samples.count,
            tokens: period == .all ? totalTokenCount : 0,
            activeDays: days.count,
            peakHour: peakLabel,
            favoriteModel: favorite ?? (period == .all ? (installedModelName ?? "—") : "—")
        )
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

    func reloadTranscript() {
        transcript = (try? store.messages(sessionID: sessionID)) ?? []
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

    func setProjectFolder(_ url: URL) {
        codeFolderName = url.lastPathComponent
        coworkProjectName = url.lastPathComponent
        guard var session = try? store.session(id: sessionID) else { return }
        session.projectPath = url.path
        try? store.updateSession(session)
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
        await sendPrompt(trimmed)
        return true
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

    var hasProjects: Bool { codeFolderName != "Select folder…" }
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
    var hasArtifacts: Bool { !createdArtifactPaths.isEmpty }
    var hasPinnedItems: Bool { taskPinned }
    var commandCount: Int {
        transcript.filter { $0.role == .tool && ($0.toolName == "bash" || $0.text.hasPrefix("Ran:")) }.count
    }
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

    func deleteCurrentTask() {
        try? store.deleteMessages(sessionID: sessionID)
        taskTitle = "Task"
        taskPinned = false
        reloadTranscript()
    }
    var recentTaskTitles: [String] {
        guard shouldShowTaskInSidebar else { return [] }
        return [taskSidebarTitle]
    }

    var taskSidebarTitle: String { taskTitle }

    private var shouldShowTaskInSidebar: Bool {
        if showTaskThread, coworkDestination == .task {
            return true
        }
        let messages = (try? store.userMessages(sessionID: sessionID)) ?? []
        return !messages.isEmpty
    }
    var messageCount: Int { transcript.count }

    var totalTokenCount: Int {
        transcript.reduce(0) { $0 + ($1.outputTokens ?? 0) }
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
        let usageURL = supportDirectory.appendingPathComponent("usage.json")
        if let data = try? Data(contentsOf: usageURL),
           let decoded = try? JSONDecoder().decode([UsageSample].self, from: data) {
            usageSamples = decoded
        }
        let directory = supportDirectory
        runner.contextCoordinator.loadUserInstructions = {
            var parts = ["instructions.md", "cowork-instructions.md"].compactMap { name -> String? in
                let url = directory.appendingPathComponent(name)
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
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
        refreshMCPLines()
        return self
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
    }

    var modelDisplayName: String {
        if let downloadStatus { return downloadStatus }
        if let installedModelName, !installedModelName.isEmpty { return installedModelName }
        return "No model"
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
            runner.useModel(installed.turn)
            installedModelName = installed.name
            if var session = try store.session(id: sessionID) {
                session.modelIdentifier = installed.identifier
                try store.updateSession(session)
            }
            downloadStatus = nil
        } catch {
            downloadStatus = "Could not download a model"
        }
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

    var knownCoworkProjectFolders: [String] {
        let path = workspaceProjectPath
        guard !path.isEmpty else { return [] }
        return [URL(fileURLWithPath: path).lastPathComponent]
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
