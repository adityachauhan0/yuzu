import AppKit
import SwiftUI
import YuzuHarness

struct CoworkHomeView: View {
    @EnvironmentObject private var model: AppModel
    let colors: ThemeColors
    @State private var prompt = ""
    @State private var addMenuOpen = false
    @State private var modelMenuOpen = false
    @State private var effortMenuOpen = false
    @State private var projectMenuOpen = false
    @State private var attachedFiles: [String] = []

    private var isDark: Bool { model.theme == .dark }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            welcomeHeading
            composerWrap
            ideas
            Spacer()
        }
        .padding(.horizontal, 24)
        .onChange(of: model.coworkSeed) { _, seed in
            guard let seed else { return }
            prompt = seed
            model.coworkSeed = nil
        }
        .dismissesOnEscape($addMenuOpen)
        .dismissesOnEscape($modelMenuOpen)
        .dismissesOnEscape($effortMenuOpen)
        .dismissesOnEscape($projectMenuOpen)
    }

    private var welcomeHeading: some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if let logo = HandoffImage.coworkLogo(dark: isDark, width: 42) {
                    logo
                        .resizable()
                        .scaledToFit()
                        .frame(width: 42, height: 42)
                } else {
                    Image(systemName: "sparkle")
                        .font(.system(size: 32))
                }
            }
            .accessibilityHidden(true)

            Text(AccountName.coworkWelcomeLine)
                .font(.custom("Georgia", size: 44))
                .foregroundStyle(colors.text)
                .tracking(-2.2)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(minHeight: 62)
        .padding(.bottom, 16)
    }

    private var composerWrap: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                TextField("How can I help you today?", text: $prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...4)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                    .onKeyPress { press in
                        guard press.key == .return else { return .ignored }
                        if press.modifiers.contains(.shift) {
                            return .ignored
                        }
                        sendTask()
                        return .handled
                    }

                HStack(spacing: 10) {
                    Button {
                        addMenuOpen.toggle()
                        modelMenuOpen = false
                        projectMenuOpen = false
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 22))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(colors.muted)
                    .accessibilityID("add-button", label: "Add to task")

                    Spacer()

                    Button {
                        modelMenuOpen.toggle()
                        addMenuOpen = false
                        projectMenuOpen = false
                    } label: {
                        Text(model.modelDisplayName)
                            .font(.system(size: 15))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(colors.text)
                    .accessibilityID("model-button")

                    Button {
                        effortMenuOpen.toggle()
                        modelMenuOpen = false
                    } label: {
                        Text(model.coworkEffortLabel)
                            .font(.system(size: 15))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(colors.text)
                    .accessibilityID("effort-label")

                    Button(action: sendTask) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? colors.dim : colors.accent)
                    .accessibilityID("send-button", label: "Send task")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .frame(minHeight: 53)
            }
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 21))
            .overlay(RoundedRectangle(cornerRadius: 21).stroke(colors.line, lineWidth: 1))

            Button {
                projectMenuOpen.toggle()
                addMenuOpen = false
                modelMenuOpen = false
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 16))
                    Text(model.coworkProjectName)
                        .font(.system(size: 15.5))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(colors.dim)
                    Spacer()
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(colors.dim)
                }
                .padding(.horizontal, 26)
                .frame(height: 49)
            }
            .buttonStyle(.plain)
            .foregroundStyle(colors.muted)
            .accessibilityID("project-button")

            if !attachedFiles.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(attachedFiles, id: \.self) { path in
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.system(size: 13))
                            .foregroundStyle(colors.dim)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: CGFloat(Tokens.contentWidth))
        .overlay(alignment: .topLeading) {
            if addMenuOpen {
                addMenu
                    .padding(.top, 120)
                    .padding(.leading, 16)
            }
        }
        .overlay(alignment: .topTrailing) {
            if modelMenuOpen {
                modelMenu
                    .padding(.top, 120)
                    .padding(.trailing, 120)
            }
            if effortMenuOpen {
                effortMenu
                    .padding(.top, 120)
                    .padding(.trailing, 56)
            }
        }
        .overlay(alignment: .topLeading) {
            if projectMenuOpen {
                projectMenu
                    .padding(.top, 169)
                    .padding(.leading, 16)
            }
        }
    }

    private var addMenu: some View {
        HandoffPopover(colors: colors) {
            HandoffMenuLabel(title: "Add to task", colors: colors)
            HandoffPopoverRow(title: "Attach a file", colors: colors) {
                addMenuOpen = false
                attachFile()
            }
            .accessibilityID("cowork-attach-file")
            HandoffPopoverRow(title: "Choose a project", colors: colors) {
                addMenuOpen = false
                projectMenuOpen = true
            }
            .accessibilityID("cowork-choose-project")
        }
    }

    private var modelMenu: some View {
        HandoffPopover(colors: colors) {
            HandoffMenuLabel(title: "Model", colors: colors)
            HandoffPopoverRow(title: model.modelDisplayName, colors: colors) {
                modelMenuOpen = false
            }
        }
    }

    private var effortMenu: some View {
        HandoffPopover(colors: colors) {
            HandoffMenuLabel(title: "Effort", colors: colors)
            ForEach(["High", "Medium", "Low"], id: \.self) { effort in
                HandoffPopoverRow(title: effort, colors: colors) {
                    model.reasoningEffort = effortValue(effort)
                    effortMenuOpen = false
                }
                .accessibilityIdentifier("cowork-effort-\(effort)")
            }
        }
    }

    private var projectMenu: some View {
        HandoffPopover(colors: colors) {
            HandoffMenuLabel(title: "Project", colors: colors)
            ForEach(model.knownProjectFolders, id: \.self) { folder in
                HandoffPopoverRow(title: folder.lastPathComponent, colors: colors) {
                    model.setProjectFolder(folder)
                    projectMenuOpen = false
                }
                .accessibilityIdentifier("cowork-project-\(folder.lastPathComponent)")
            }
            HandoffPopoverRow(title: "No project", colors: colors) {
                model.clearProjectFolder()
                projectMenuOpen = false
            }
            .accessibilityID("cowork-project-none")
            HandoffPopoverRow(title: "Choose a folder", colors: colors) {
                projectMenuOpen = false
                chooseProjectFolder()
            }
            .accessibilityID("cowork-choose-folder")
        }
    }

    private var ideas: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ideas for you")
                .font(.system(size: 14))
                .foregroundStyle(colors.dim)
            HStack {
                ideaButton("Send me a daily briefing")
                ideaButton("Organize my inbox")
                ideaButton("Customize Cowork for me")
            }
        }
        .frame(maxWidth: CGFloat(Tokens.contentWidth), alignment: .leading)
    }

    private func ideaButton(_ title: String) -> some View {
        Button {
            prompt = title
        } label: {
            Text(title)
                .font(.system(size: 14))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .foregroundStyle(colors.muted)
    }

    private func sendTask() {
        let attachment = attachedFiles.map { "Attached file: \($0)" }.joined(separator: "\n")
        let body = [prompt, attachment].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n")
        Task {
            if await model.submitCoworkHomeTask(body) {
                prompt = ""
                attachedFiles = []
            }
        }
    }

    private func effortValue(_ label: String) -> ReasoningEffort {
        switch label {
        case "Low": return .low
        case "Medium": return .medium
        default: return .high
        }
    }

    private func chooseProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.setProjectFolder(url)
        }
    }

    private func attachFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            attachedFiles.append(contentsOf: panel.urls.map(\.path))
        }
    }
}
