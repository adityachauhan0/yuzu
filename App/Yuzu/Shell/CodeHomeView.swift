import AppKit
import SwiftUI
import YuzuHarness

enum CodeUsageTab: String, CaseIterable {
    case overview = "Overview"
    case models = "Models"
}

enum CodeUsagePeriod: String, CaseIterable {
    case all = "All"
    case days30 = "30d"
    case days7 = "7d"
}

struct CodeHomeView: View {
    @EnvironmentObject private var model: AppModel
    let colors: ThemeColors
    @State private var prompt = ""
    @State private var usageTab: CodeUsageTab = .overview
    @State private var modelMenuOpen = false
    @State private var effortMenuOpen = false
    @State private var addMenuOpen = false
    @State private var attachments: [String] = []

    private var isDark: Bool { model.theme == .dark }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heading
                    usageCard
                    if let preview = model.codeTaskPreview {
                        Button {
                            model.openTask(model.sessionID)
                        } label: {
                            Text(preview)
                                .font(.system(size: 15))
                                .foregroundStyle(colors.softText)
                                .multilineTextAlignment(.leading)
                                .padding(.vertical, 9)
                                .padding(.horizontal, 12)
                                .background(colors.preview)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 20)
                        .padding(.leading, 10)
                        .accessibilityID("code-task-preview", label: preview)
                    }
                }
                .frame(maxWidth: CGFloat(Tokens.contentWidth), alignment: .leading)
                .padding(.top, 55)
            }
            footer
                .frame(maxWidth: CGFloat(Tokens.contentWidth))
                .padding(.bottom, 18)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .dismissesOnEscape($addMenuOpen)
        .dismissesOnEscape($modelMenuOpen)
    }

    private var heading: some View {
        HStack(alignment: .center, spacing: 7) {
            Button {
                model.selectCowork(.new)
            } label: {
                Group {
                    if let logo = HandoffImage.coworkLogo(dark: isDark, width: 42) {
                        logo
                            .resizable()
                            .scaledToFit()
                            .frame(width: 42, height: 42)
                    } else {
                        Image(systemName: "sparkle").font(.system(size: 20))
                    }
                }
                .accessibilityIdentifier("data-mascot-cowork")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Return to Cowork")

            Text("What's up next, \(AccountName.firstName)?")
                .font(.system(size: 25, weight: .regular))
                .foregroundStyle(colors.text)
                .tracking(-0.6)
        }
    }

    private var usageCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 3) {
                    ForEach(CodeUsageTab.allCases, id: \.self) { tab in
                        usageTabButton(tab)
                    }
                }
                Spacer()
                HStack(spacing: 3) {
                    ForEach(CodeUsagePeriod.allCases, id: \.self) { period in
                        usagePeriodButton(period)
                    }
                }
            }
            .padding(.bottom, 23)

            if usageTab == .overview {
                overviewPanel
            } else {
                modelsPanel
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 13)
        .frame(maxWidth: 576, alignment: .leading)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.top, 55)
        .padding(.leading, 10)
        .accessibilityLabel("Code usage")
    }

    private func usageTabButton(_ tab: CodeUsageTab) -> some View {
        let selected = usageTab == tab
        return Button {
            usageTab = tab
        } label: {
            Text(tab.rawValue)
                .font(.system(size: 14))
                .padding(.horizontal, 7)
                .padding(.vertical, 1)
                .background(selected ? colors.selected : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(selected ? colors.text : colors.dim)
        }
        .buttonStyle(.plain)
    }

    private func usagePeriodButton(_ period: CodeUsagePeriod) -> some View {
        let selected = model.usagePeriod == period
        return Button {
            model.usagePeriod = period
        } label: {
            Text(period.rawValue)
                .font(.system(size: 14))
                .padding(.horizontal, 7)
                .padding(.vertical, 1)
                .background(selected ? colors.selected : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(selected ? colors.text : colors.dim)
        }
        .buttonStyle(.plain)
    }

    private var overviewPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            let metrics = model.usageMetrics(period: model.usagePeriod)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3),
                spacing: 5
            ) {
                codeMetric("Sessions", value: "\(metrics.sessions)")
                codeMetric("Messages", value: "\(metrics.messages)")
                codeMetric("Total tokens", value: "\(metrics.tokens)")
                codeMetric("Active days", value: "\(metrics.activeDays)")
                codeMetric("Peak hour", value: metrics.peakHour)
                codeMetric("Favorite model", value: metrics.favoriteModel, small: true)
            }

            heatmap

            if metrics.tokens > 0 {
                Text(model.gatsbyUsageNote)
                    .font(.system(size: 13))
                    .foregroundStyle(colors.dim)
                    .padding(.top, 5)
            }
        }
    }

    private var modelsPanel: some View {
        let shares = model.modelShares(period: model.usagePeriod)
        return VStack(spacing: 5) {
            ForEach(Array(shares.enumerated()), id: \.offset) { index, entry in
                HStack {
                    Text(entry.name)
                        .font(.system(size: 15))
                        .foregroundStyle(colors.text)
                    Spacer()
                    Text(index == 0 ? "Favorite model" : entry.share.formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(size: 13))
                        .foregroundStyle(colors.subtle)
                }
                .padding(.horizontal, 9)
                .frame(minHeight: 54)
                .background(colors.selected)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityID("code-model-row")
            }
        }
        .frame(minHeight: 162, alignment: .top)
    }

    private func codeMetric(_ title: String, value: String, small: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(colors.dim)
                .lineLimit(1)
            Text(value)
                .font(.system(size: small ? 14 : 16, weight: small ? .regular : .medium))
                .foregroundStyle(colors.text)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(colors.selected)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var heatmap: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 26),
            spacing: 4
        ) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(level == 2 ? colors.accent : level == 1 ? colors.heatLow : colors.line)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .padding(.top, 7)
        .accessibilityElement(children: .ignore)
        .accessibilityID("code-heatmap", label: heatmapLabel)
    }

    private var levels: [Int] { model.activityLevels() }

    private var heatmapLabel: String {
        let active = levels.filter { $0 > 0 }.count
        return "Activity over time, \(active) active day\(active == 1 ? "" : "s")"
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    TextField("Describe a task or ask a question", text: $prompt, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...6)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .foregroundStyle(colors.text)
                        .font(.system(size: 16))
                        .onKeyPress { press in
                            guard press.key == .return, !press.modifiers.contains(.shift) else { return .ignored }
                            send()
                            return .handled
                        }
                        .accessibilityID("code-prompt", label: "Describe a task or ask a question")

                    HStack {
                        Spacer()
                        Button(action: send) {
                            Image(systemName: "arrow.turn.down.left")
                                .font(.system(size: 15))
                                .frame(width: 40, height: 40)
                                .background(promptReady ? colors.surfaceHover : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(promptReady ? colors.softText : colors.dim)
                        .accessibilityID(promptReady ? "code-submit-ready" : "code-submit", label: "Send Code task")
                    }
                    .padding(.trailing, 5)
                }
                .background(colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(colors.line, lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    Button {
                        chooseCodeFolder()
                    } label: {
                        Label(model.codeFolderName, systemImage: "folder")
                            .font(.system(size: 14))
                            .lineLimit(1)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(colors.surfaceHover)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(colors.muted)
                    .accessibilityID("code-folder")
                    .padding(.leading, 16)
                    .offset(y: -36)
                }

                if let mascot = HandoffImage.codeMascot(dark: isDark, width: 56) {
                    mascot
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56)
                        .padding(.trailing, 16)
                        .padding(.bottom, 83)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("data-mascot-code")
                }
            }

            HStack(spacing: 11) {
                Button {
                    addMenuOpen.toggle()
                    modelMenuOpen = false
                } label: {
                    Text("+")
                        .font(.system(size: 23))
                        .foregroundStyle(colors.dim)
                        .frame(width: 26)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add context")

                Button {
                    Task { await model.toggleManual() }
                } label: {
                    Text(model.permissionPosture.label)
                        .font(.system(size: 14))
                        .foregroundStyle(colors.accent)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
                .accessibilityID("code-manual", label: model.permissionPosture.label)

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        modelMenuOpen.toggle()
                        effortMenuOpen = false
                    } label: {
                        Label(model.modelDisplayName, systemImage: "cpu")
                            .font(.system(size: 14))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .frame(maxWidth: 220, alignment: .leading)
                            .background(colors.surfaceHover)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(colors.muted)
                    .accessibilityID("code-model-button")

                    Text(model.speedLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(colors.dim)
                        .accessibilityID("code-speed", label: model.speedLabel == "—" ? "speed —" : "speed \(model.speedLabel)")
                }

                Button {
                    effortMenuOpen.toggle()
                    modelMenuOpen = false
                } label: {
                    Text(model.coworkEffortLabel)
                        .font(.system(size: 14))
                        .foregroundStyle(colors.text)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
                .accessibilityID("code-effort")
            }

            if !attachments.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(attachments, id: \.self) { path in
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.system(size: 13))
                            .foregroundStyle(colors.dim)
                            .lineLimit(1)
                    }
                }
                .accessibilityID("code-attachments")
            }
        }
        .padding(.top, 20)
        .overlay(alignment: .bottomLeading) {
            if addMenuOpen {
                HandoffPopover(colors: colors) {
                    HandoffMenuLabel(title: "Add context", colors: colors)
                    HandoffPopoverRow(title: "Attach a file", colors: colors) {
                        addMenuOpen = false
                        attachContext()
                    }
                    .accessibilityID("code-attach-file")
                    HandoffPopoverRow(title: "Choose a project", colors: colors) {
                        addMenuOpen = false
                        chooseCodeFolder()
                    }
                    .accessibilityID("code-choose-project")
                }
                .frame(width: 220)
                .padding(.bottom, 36)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if modelMenuOpen {
                HandoffPopover(colors: colors) {
                    HandoffMenuLabel(title: "Model", colors: colors)
                    HandoffPopoverRow(title: model.modelDisplayName, colors: colors) {
                        modelMenuOpen = false
                    }
                }
                .frame(width: 220, alignment: .leading)
                .padding(.bottom, 36)
                .padding(.trailing, 8)
            }
            if effortMenuOpen {
                HandoffPopover(colors: colors) {
                    HandoffMenuLabel(title: "Effort", colors: colors)
                    ForEach(["High", "Medium", "Low"], id: \.self) { effort in
                        HandoffPopoverRow(title: effort, colors: colors) {
                            model.reasoningEffort = ReasoningEffort.fromLabel(effort)
                            effortMenuOpen = false
                        }
                    }
                }
                .frame(width: 200, alignment: .leading)
                .padding(.bottom, 36)
                .padding(.trailing, 8)
            }
        }
        .dismissesOnEscape($effortMenuOpen)
    }

    private var promptReady: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let body = ComposerContext.prompt(prompt, attachments: attachments)
        guard promptReady else { return }
        prompt = ""
        attachments = []
        Task { await model.sendPrompt(body, newTask: true) }
    }

    private func chooseCodeFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.setProjectFolder(url)
        }
    }

    private func attachContext() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            attachments.append(contentsOf: panel.urls.map(\.path).filter { !attachments.contains($0) })
        }
    }
}
