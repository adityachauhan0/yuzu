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

    private var isDark: Bool { model.theme == .dark }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heading
                    usageCard
                }
                .frame(maxWidth: CGFloat(Tokens.contentWidth), alignment: .leading)
                .padding(.top, 55)
            }
            footer
                .frame(maxWidth: CGFloat(Tokens.contentWidth))
                .padding(.bottom, 3)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

            if model.totalTokenCount > 0 {
                Text(model.gatsbyUsageNote)
                    .font(.system(size: 13))
                    .foregroundStyle(colors.dim)
                    .padding(.top, 5)
            }
        }
    }

    private var modelsPanel: some View {
        HStack {
            Text(model.modelDisplayName)
                .font(.system(size: 15))
                .foregroundStyle(colors.text)
            Spacer()
            Text("Favorite model")
                .font(.system(size: 13))
                .foregroundStyle(colors.dim)
        }
        .padding(.horizontal, 9)
        .frame(minHeight: 54)
        .background(colors.selected)
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
            ForEach(0..<26, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 2)
                    .fill(colors.line)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .accessibilityLabel("Activity over time")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button {
                } label: {
                    Label("Local", systemImage: "rectangle.split.3x1")
                        .font(.system(size: 14))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(colors.selected)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .foregroundStyle(colors.muted)
                .accessibilityID("code-local")

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
            }

            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    TextField("Describe a task or ask a question", text: $prompt, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...6)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .foregroundStyle(colors.text)
                        .font(.system(size: 16))

                    HStack {
                        Spacer()
                        Button {
                            Task { await model.sendPrompt(prompt) }
                        } label: {
                            Image(systemName: "arrow.turn.down.left")
                                .font(.system(size: 15))
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(colors.dim)
                    }
                    .padding(.trailing, 5)
                }
                .background(colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(colors.line, lineWidth: 1))

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
                    attachContext()
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
                    Text("Manual")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(red: 0.89, green: 0.67, blue: 0.02))
                        .padding(.horizontal, 4)
                        .background(model.manualPressed ? colors.selected.opacity(0.5) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .accessibilityID("code-manual")

                Spacer()

                HStack(spacing: 5) {
                    Button {
                        modelMenuOpen.toggle()
                    } label: {
                        Text(model.modelDisplayName)
                            .font(.system(size: 14))
                            .foregroundStyle(colors.text)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityID("code-model-button")

                    Text(model.speedLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(colors.dim)
                        .accessibilityID("code-speed", label: model.speedLabel == "—" ? "speed —" : "speed \(model.speedLabel)")
                }

                Button {
                    modelMenuOpen.toggle()
                } label: {
                    Text(model.coworkEffortLabel)
                        .font(.system(size: 14))
                        .foregroundStyle(colors.text)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
                .accessibilityID("code-effort")
            }
            .padding(.top, 5)
        }
        .padding(.top, 20)
        .overlay(alignment: .bottomTrailing) {
            if modelMenuOpen {
                HandoffPopover(colors: colors) {
                    HandoffMenuLabel(title: "Model and effort", colors: colors)
                    ForEach(["High", "Medium", "Low"], id: \.self) { effort in
                        HandoffPopoverRow(
                            title: "\(model.modelDisplayName) · \(effort)",
                            colors: colors
                        ) {
                            model.reasoningEffort = codeEffort(effort)
                            modelMenuOpen = false
                        }
                    }
                }
                .padding(.bottom, 36)
            }
        }
    }

    private func codeEffort(_ label: String) -> ReasoningEffort {
        switch label {
        case "Low": return .low
        case "Medium": return .medium
        default: return .high
        }
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
            let paths = panel.urls.map(\.path).joined(separator: "\n")
            if prompt.isEmpty {
                prompt = paths
            } else {
                prompt += "\n" + paths
            }
        }
    }
}
