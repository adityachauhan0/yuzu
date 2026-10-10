import AppKit
import SwiftUI
import UniformTypeIdentifiers
import YuzuHarness

struct SettingsDialog: View {
    @EnvironmentObject private var model: AppModel
    let colors: ThemeColors
    @State private var trustedRefresh = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { model.settingsPresented = false }

            HStack(spacing: 0) {
                settingsSidebar
                settingsMain
            }
            .frame(width: 820, height: 560)
            .background(colors.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(colors.line, lineWidth: 1))
            .accessibilityID("settings-dialog")
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.system(size: 13))
                .foregroundStyle(colors.dim)
                .padding(.horizontal, 12)
                .padding(.top, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        Button {
                            model.settingsTab = tab
                        } label: {
                            Text(tab.rawValue)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(model.settingsTab == tab ? colors.selected : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(colors.text)
                        .accessibilityIdentifier("settings-tab-\(tab.rawValue)")
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 200)
        .background(colors.side)
    }

    @ViewBuilder
    private var settingsMain: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch model.settingsTab {
                case .general: generalPanel
                case .privacy: privacyPanel
                case .usage: usagePanel
                case .code: codePanel
                case .cowork: coworkPanel
                case .importExport: importExportPanel
                case .system: systemPanel
                case .developer: developerPanel
                case .skills: skillsPanel
                case .connectors: connectorsPanel
                case .plugins: pluginsPanel
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var generalPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("General")
                .accessibilityID("settings-general-heading")
            Text("What best describes your work?")
                .foregroundStyle(colors.muted)
            segment(options: ["Select", "Engineering", "Design", "Research", "Writing", "Other"], selection: $model.workDescription)
            Text("Instructions for Yuzu")
                .foregroundStyle(colors.muted)
            TextField("Instructions for Yuzu", text: $model.yuzuInstructions, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.plain)
                .padding(10)
                .background(colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.line, lineWidth: 1))
                .onChange(of: model.yuzuInstructions) { _, _ in
                    model.saveInstructions()
                }
            Text("Theme")
                .foregroundStyle(colors.muted)
            themePicker
            Text("Chat font")
                .foregroundStyle(colors.muted)
            segment(options: ["Serif", "System"], selection: $model.chatFont)
            Text("Motion")
                .foregroundStyle(colors.muted)
            segment(options: ["System", "Reduced"], selection: $model.motionSetting)
            Toggle("Response completions", isOn: Binding(
                get: { model.responseCompletions },
                set: { model.setResponseCompletions($0) }
            ))
            .toggleStyle(.switch)
            .foregroundStyle(colors.text)
        }
    }

    private var privacyPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Privacy")
            settingsRow("Transcripts and weights", "On this Mac")
            settingsRow("Store", model.storeFilePath)
            callout("Sessions are not uploaded.")
        }
    }

    private var usagePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            let metrics = model.usageMetrics(period: model.usagePeriod)
            heading("Usage")
            settingsRow("Sessions", "\(metrics.sessions)")
            settingsRow("Messages", "\(metrics.messages)")
            settingsRow("Total tokens", "\(metrics.tokens)")
            settingsRow("Active days", "\(metrics.activeDays)")
            settingsRow("Peak hour", metrics.peakHour)
            settingsRow("Favorite model", metrics.favoriteModel)
        }
    }

    private var codePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Code appearance")
                .accessibilityID("settings-code-appearance-heading")
                .accessibilityLabel("Code appearance")
            settingsRow("Light theme", "GitHub Light / Default Light")
            settingsRow("Dark theme", "GitHub Dark / Default Dark")
            Text("Code font")
                .foregroundStyle(colors.muted)
            TextField("e.g. JetBrains Mono", text: $model.codeFont)
                .textFieldStyle(.plain)
                .padding(10)
                .background(colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.line, lineWidth: 1))
            Text("func greet() {}")
                .font(YuzuFonts.code(model.codeFont, size: 14))
                .foregroundStyle(colors.text)
                .accessibilityID("code-font-preview")
            Text("Interface font")
                .foregroundStyle(colors.muted)
            segment(options: ["System", "Serif", "OpenDyslexic"], selection: $model.interfaceFont)
            Text("Transcript text size")
                .foregroundStyle(colors.muted)
            segment(options: ["Small", "Medium", "Large"], selection: $model.transcriptSize)
            Text("Transcript width")
                .foregroundStyle(colors.muted)
            segment(options: ["Narrow", "Medium", "Wide"], selection: $model.transcriptWidth)
            Text("Default transcript view")
                .foregroundStyle(colors.muted)
            segment(options: ["Normal", "Thinking", "Verbose"], selection: $model.transcriptView)
            Text("Sessions")
                .foregroundStyle(colors.muted)
            if model.messageCount == 0 {
                callout("No sessions yet.")
            } else {
                settingsRow(model.taskSidebarTitle, URL(fileURLWithPath: model.workspaceProjectPath).lastPathComponent)
            }
        }
    }

    private var coworkPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Cowork")
            settingsRow("Files", model.workspaceProjectPath)
            plainButton("Change") { chooseCoworkFolder() }
            Text("Trusted folders are paths Yuzu may use without asking again.")
                .foregroundStyle(colors.muted)
            let folders = trustedFolders
            if folders.isEmpty {
                callout("No trusted folders added.")
            } else {
                ForEach(folders, id: \.self) { folder in
                    settingsRow("Allowed", folder)
                }
            }
            plainButton("Manage") { chooseTrustedFolder() }
            Text("Global instructions")
                .foregroundStyle(colors.muted)
            TextField("Global instructions", text: $model.coworkInstructions, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.plain)
                .padding(10)
                .background(colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onChange(of: model.coworkInstructions) { _, _ in
                    model.saveInstructions()
                }
            Toggle("Memory", isOn: Binding(
                get: { model.memoryEnabled },
                set: { model.setMemoryEnabled($0) }
            ))
            .toggleStyle(.switch)
            .foregroundStyle(colors.text)
            callout("Yuzu saves memories on this device.")
            if model.memories.isEmpty {
                callout("No memories yet. Yuzu will add entries here as you work together.")
            } else {
                ForEach(model.memories, id: \.self) { memory in
                    settingsRow("Memory", memory)
                }
            }
        }
    }

    private var trustedFolders: [String] {
        _ = trustedRefresh
        return model.trustedFolderPaths()
    }

    private var importExportPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Import & export")
            plainButton("Export sessions") { exportSessions() }
            plainButton("Import sessions") { importSessions() }
        }
    }

    private var systemPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("System")
            settingsRow("App version", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.1")
            settingsRow("uzu", "0.6.2")
            settingsRow("Loaded model", model.modelDisplayName)
            plainButton("Open logs") {
                NSWorkspace.shared.open(model.supportDirectory)
            }
        }
    }

    private var developerPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Developer")
            Text("Local MCP servers")
                .foregroundStyle(colors.muted)
            if model.mcpServerLines.isEmpty {
                callout("No servers added.")
            } else {
                ForEach(model.mcpServerLines, id: \.self) { line in
                    settingsRow("Server", line)
                    if line.contains("needs auth") {
                        let name = line.split(separator: "·").first.map {
                            $0.trimmingCharacters(in: .whitespaces)
                        } ?? ""
                        if !name.isEmpty {
                            plainButton("Sign in") { model.beginMCPSignIn(serverName: name) }
                        }
                    }
                }
            }
            Text("Edit config")
                .foregroundStyle(colors.muted)
            TextField("mcp_servers", text: $model.mcpConfig, axis: .vertical)
                .lineLimit(4...8)
                .font(.system(size: 13, design: .monospaced))
                .textFieldStyle(.plain)
                .padding(10)
                .background(colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityID("mcp-config")
                .onChange(of: model.mcpConfig) { _, _ in
                    model.saveMCPConfig()
                }
            plainButton("Developer docs") {
                if let url = URL(string: "https://modelcontextprotocol.io/introduction") {
                    NSWorkspace.shared.open(url)
                }
            }
            heading("Inference")
            settingsRow("Engine", "uzu 0.6.2")
            settingsRow("Context length", "\(model.loadedContextLength)")
            settingsRow("Sampling", "greedy")
        }
    }

    private var skillsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Skills")
            let skills = SkillCatalog.discover(projectPath: model.workspaceProjectPath)
            if skills.isEmpty {
                callout("Skills teach Yuzu how you work.")
            } else {
                ForEach(skills, id: \.name) { skill in
                    settingsRow(skill.name, skill.description.isEmpty ? "This skill has no description." : skill.description)
                }
            }
            plainButton("Open Customize") {
                model.settingsPresented = false
                model.selectCowork(.customize)
            }
        }
    }

    private var connectorsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Connectors")
            callout("No servers added.")
            plainButton("Add") { model.settingsTab = .developer }
        }
    }

    private var pluginsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Plugins")
            callout("No plugins yet.")
        }
    }

    private var themePicker: some View {
        segment(
            options: AppTheme.allCases.map(\.rawValue.capitalized),
            selection: Binding(
                get: { model.theme.rawValue.capitalized },
                set: { label in
                    if let theme = AppTheme.allCases.first(where: { $0.rawValue.capitalized == label }) {
                        model.theme = theme
                    }
                }
            )
        )
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(colors.text)
    }

    private func settingsRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(colors.text)
            Spacer()
            Text(value)
                .foregroundStyle(colors.muted)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .font(.system(size: 14))
    }

    private func callout(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(colors.dim)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func segment(options: [String], selection: Binding<String>) -> some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { option in
                Button(option) { selection.wrappedValue = option }
                    .buttonStyle(.plain)
                    .font(.system(size: 14))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(selection.wrappedValue == option ? colors.selected : Color.clear)
                    .foregroundStyle(colors.text)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func plainButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 14))
            .foregroundStyle(colors.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(colors.surfaceHover)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.line, lineWidth: 1))
    }

    private func chooseCoworkFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.coworkProjectName = url.lastPathComponent
        }
    }

    private func chooseTrustedFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.allowTrustedFolder(url.path)
            trustedRefresh += 1
        }
    }

    private func exportSessions() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "yuzu-sessions.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.exportSessionJSON().write(to: url)
            model.showToast("Exported sessions.")
        } catch {
            model.showToast("Could not export sessions.")
        }
    }

    private func importSessions() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.importSessionJSON(Data(contentsOf: url))
            model.showToast("Imported sessions.")
        } catch {
            model.showToast("Could not import sessions.")
        }
    }
}
