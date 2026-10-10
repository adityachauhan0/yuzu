import AppKit
import SwiftUI
import UniformTypeIdentifiers
import YuzuHarness
import YuzuModel

struct SettingsDialog: View {
    @EnvironmentObject private var model: AppModel
    let colors: ThemeColors
    @State private var trustedRefresh = 0
    @State private var tabSearch = ""
    @State private var fontLicensesOpen = false
    @FocusState private var mcpFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            let stacked = proxy.size.width <= 620
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { model.settingsPresented = false }

                Group {
                    if stacked {
                        VStack(spacing: 0) {
                            settingsSidebar(stacked: true)
                            settingsMain
                        }
                    } else {
                        HStack(spacing: 0) {
                            settingsSidebar(stacked: false)
                            settingsMain
                        }
                    }
                }
                .overlay(alignment: .topTrailing) { settingsClose }
                .frame(width: stacked ? proxy.size.width : 820, height: stacked ? proxy.size.height : 560)
                .background(colors.canvas)
                .clipShape(RoundedRectangle(cornerRadius: stacked ? 0 : 14))
                .overlay(RoundedRectangle(cornerRadius: stacked ? 0 : 14).stroke(colors.line, lineWidth: stacked ? 0 : 1))
                .accessibilityID("settings-dialog")

                if fontLicensesOpen {
                    fontLicensesDialog
                }
            }
        }
        .dismissesOnEscape($fontLicensesOpen)
    }

    private var settingsClose: some View {
        Button {
            model.settingsPresented = false
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .foregroundStyle(colors.muted)
        .padding(10)
        .accessibilityID("settings-close", label: "Close settings")
    }

    private static let groups: [(label: String, tabs: [SettingsTab])] = [
        ("Settings", [.general, .privacy, .usage, .code, .cowork, .importExport]),
        ("This computer", [.system, .developer]),
        ("Customize", [.skills, .connectors]),
    ]

    private func settingsSidebar(stacked: Bool) -> some View {
        let term = tabSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundStyle(colors.subtle)
                TextField("Search", text: $tabSearch)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(colors.softText)
                    .accessibilityID("settings-search", label: "Search settings")
            }
            .padding(.horizontal, 11)
            .frame(height: 40)
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(colors.line, lineWidth: 1))
            .padding(.bottom, stacked ? 10 : 22)
            if stacked {
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(visibleTabs(term), id: \.self) { tab in
                            tabButton(tab, showIcon: false)
                        }
                    }
                }
                .scrollIndicators(.never)
            } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Self.groups, id: \.label) { group in
                        let tabs = group.tabs.filter { term.isEmpty || $0.rawValue.lowercased().contains(term) }
                        if !tabs.isEmpty {
                            Text(group.label)
                                .font(.system(size: 13))
                                .foregroundStyle(colors.dim)
                                .padding(.horizontal, 10)
                                .padding(.bottom, 4)
                            ForEach(tabs, id: \.self) { tab in
                                tabButton(tab, showIcon: true)
                            }
                            Color.clear.frame(height: 16)
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            }
        }
        .padding(16)
        .frame(maxWidth: stacked ? .infinity : 230, maxHeight: stacked ? 176 : .infinity, alignment: .topLeading)
        .frame(width: stacked ? nil : 230)
        .background(colors.side)
    }

    private func visibleTabs(_ term: String) -> [SettingsTab] {
        Self.groups.flatMap(\.tabs).filter { term.isEmpty || $0.rawValue.lowercased().contains(term) }
    }

    private func tabButton(_ tab: SettingsTab, showIcon: Bool) -> some View {
        Button {
            model.settingsTab = tab
        } label: {
            HStack(spacing: 10) {
                if showIcon {
                    Image(systemName: icon(for: tab))
                        .font(.system(size: 14))
                        .frame(width: 18)
                }
                Text(tab.rawValue)
                if showIcon { Spacer(minLength: 0) }
            }
            .font(.system(size: 15))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(model.settingsTab == tab ? colors.selected : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(model.settingsTab == tab ? colors.text : colors.muted)
        .accessibilityIdentifier("settings-tab-\(tab.rawValue)")
    }

    private func icon(for tab: SettingsTab) -> String {
        switch tab {
        case .general: "gearshape"
        case .privacy: "shield"
        case .usage: "chart.bar"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .cowork: "person.2"
        case .importExport: "square.and.arrow.down"
        case .system: "desktopcomputer"
        case .developer: "wrench"
        case .skills: "puzzlepiece.extension"
        case .connectors: "slider.horizontal.3"
        }
    }

    @ViewBuilder
    private var settingsMain: some View {
        ScrollViewReader { proxy in
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
                    case .skills: CustomizeView(colors: colors, embeddedTab: .skills)
                    case .connectors: CustomizeView(colors: colors, embeddedTab: .connectors)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: model.settingsAnchor, initial: true) { _, _ in
                revealAnchor(proxy)
            }
        }
    }

    private func revealAnchor(_ proxy: ScrollViewProxy) {
        guard model.settingsTab == .developer, let anchor = model.settingsAnchor else { return }
        DispatchQueue.main.async {
            switch anchor {
            case .mcpConfig:
                proxy.scrollTo("mcp-config", anchor: .center)
                mcpFocused = true
            case .inference:
                proxy.scrollTo("settings-inference", anchor: .top)
            }
        }
    }

    private var generalPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("General")
                .accessibilityID("settings-general-heading")
            HStack {
                Text("Avatar")
                    .foregroundStyle(colors.text)
                Spacer()
                Button(action: chooseAvatar) {
                    avatarMark
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                        .background(Circle().fill(colors.surfaceHover))
                }
                .buttonStyle(.plain)
                .accessibilityID("settings-avatar", label: "Choose avatar")
            }
            Text("What best describes your work?")
                .foregroundStyle(colors.muted)
            segment(options: ["Select", "Engineering", "Design", "Research", "Writing", "Other"], selection: $model.workDescription)
                .onChange(of: model.workDescription) { _, _ in
                    model.saveWorkDescription()
                }
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
            segment(options: YuzuFonts.chatChoices, selection: $model.chatFont)
            Text("Motion")
                .foregroundStyle(colors.muted)
            segment(options: ["System", "Reduced"], selection: $model.motionSetting)
            HStack {
                Text("Response completions")
                    .foregroundStyle(colors.text)
                Spacer()
                YuzuSwitch(
                    colors: colors,
                    isOn: Binding(
                        get: { model.responseCompletions },
                        set: { model.setResponseCompletions($0) }
                    ),
                    accessibilityID: "response-completions-switch"
                )
            }
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
            HStack(spacing: 4) {
                ForEach(CodeUsagePeriod.allCases, id: \.self) { period in
                    let selected = model.usagePeriod == period
                    Button(period.rawValue) { model.usagePeriod = period }
                        .buttonStyle(.plain)
                        .font(.system(size: 14))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(selected ? colors.selected : Color.clear)
                        .foregroundStyle(selected ? colors.text : colors.dim)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .accessibilityIdentifier("settings-usage-\(period.rawValue)")
                }
            }
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
            HStack(alignment: .top, spacing: 16) {
                codeThemeColumn(
                    label: "Light code theme",
                    id: "settings-light-theme",
                    themes: CodeTheme.light,
                    selection: $model.lightCodeTheme,
                    dark: false
                )
                codeThemeColumn(
                    label: "Dark code theme",
                    id: "settings-dark-theme",
                    themes: CodeTheme.dark,
                    selection: $model.darkCodeTheme,
                    dark: true
                )
            }
            Text("Code font")
                .foregroundStyle(colors.muted)
            TextField("e.g. JetBrains Mono", text: $model.codeFont)
                .textFieldStyle(.plain)
                .padding(10)
                .background(colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.line, lineWidth: 1))
            Text("Interface font")
                .foregroundStyle(colors.muted)
            segment(options: YuzuFonts.interfaceChoices, selection: $model.interfaceFont)
            plainButton("Font licenses") { fontLicensesOpen = true }
                .accessibilityID("font-licenses")
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
            let tasks = model.taskSessions.filter { $0.messageCount > 0 }
            if tasks.isEmpty {
                callout("No sessions yet.")
            } else {
                VStack(spacing: 5) {
                    ForEach(tasks) { task in
                        Button {
                            model.settingsPresented = false
                            model.openTask(task.id)
                        } label: {
                            HStack {
                                Text(task.displayTitle)
                                    .font(.system(size: 15))
                                    .foregroundStyle(colors.text)
                                    .lineLimit(1)
                                Spacer()
                                Text(task.projectPath == model.defaultWorkspacePath
                                     ? "No project" : URL(fileURLWithPath: task.projectPath).lastPathComponent)
                                    .font(.system(size: 13))
                                    .foregroundStyle(colors.subtle)
                            }
                            .padding(.horizontal, 9)
                            .frame(minHeight: 54)
                            .background(colors.selected)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityID("settings-session-row", label: task.displayTitle)
                    }
                }
            }
        }
    }

    private func codeThemeColumn(
        label: String,
        id: String,
        themes: [CodeTheme],
        selection: Binding<String>,
        dark: Bool
    ) -> some View {
        let theme = model.activeCodeTheme(dark: dark)
        return VStack(alignment: .leading, spacing: 14) {
            Picker(label, selection: selection) {
                ForEach(themes, id: \.self) { theme in
                    Text(theme.rawValue).tag(theme.rawValue)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityID(id, label: label)
            CodeThemePreview(theme: theme, codeFont: model.codeFont)
                .accessibilityID(dark ? "code-preview-dark" : "code-font-preview", label: dark ? "Dark theme code preview" : "Light theme code preview")
        }
        .frame(maxWidth: .infinity)
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
            HStack {
                Text("Memory")
                    .foregroundStyle(colors.text)
                Spacer()
                YuzuSwitch(
                    colors: colors,
                    isOn: Binding(
                        get: { model.memoryEnabled },
                        set: { model.setMemoryEnabled($0) }
                    ),
                    accessibilityID: "memory-switch"
                )
            }
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
                model.openLogs()
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
                .id("mcp-config")
                .focused($mcpFocused)
                .onChange(of: model.mcpConfig) { _, _ in
                    model.saveMCPConfig()
                }
            plainButton("Developer docs") {
                if let url = URL(string: "https://modelcontextprotocol.io/introduction") {
                    NSWorkspace.shared.open(url)
                }
            }
            heading("Inference")
                .id("settings-inference")
            settingsRow("Engine", "uzu 0.6.2")
            settingsRow("Context length", "\(model.loadedContextLength)")
            settingsRow("Sampling", UzuTurn.samplingLabel)
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

    private var avatarMark: some View {
        Group {
            if let image = NSImage(contentsOf: model.avatarFileURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text("?")
                    .font(.system(size: 17))
                    .foregroundStyle(colors.softText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(colors.surfaceHover)
            }
        }
        .id(model.avatarRevision)
    }

    private func chooseAvatar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return }
        model.saveAvatar(png: png)
    }

    private var fontLicensesDialog: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { fontLicensesOpen = false }
            VStack(alignment: .leading, spacing: 12) {
                Text("Font licenses")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(colors.text)
                ScrollView {
                    Text(fontLicenseText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(colors.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 280)
                HStack {
                    Spacer()
                    Button("Close") { fontLicensesOpen = false }
                        .buttonStyle(.plain)
                        .font(.system(size: 15))
                        .foregroundStyle(colors.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(colors.surfaceHover)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.line, lineWidth: 1))
                        .accessibilityID("font-licenses-close")
                }
            }
            .padding(23)
            .frame(width: 500)
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(colors.line, lineWidth: 1))
            .accessibilityID("skill-dialog")
        }
    }

    private var fontLicenseText: String {
        ["Inter-OFL", "SourceSerif4-OFL", "OpenDyslexic-OFL"].compactMap { name in
            let url = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Fonts")
                ?? Bundle.main.url(forResource: name, withExtension: "txt")
            return url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        }.joined(separator: "\n\n")
    }

    private func chooseCoworkFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.setProjectFolder(url)
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
