import AppKit
import SwiftUI
import YuzuHarness

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    let colors: ThemeColors
    let reduceMotion: Bool
    @State private var accountOpen = false
    @State private var languageOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            windowBar

            ModeSwitch(colors: colors, reduceMotion: reduceMotion)
                .padding(.horizontal, 10)
                .padding(.bottom, 14)
                .accessibilityID("mode-switch")

            VStack(spacing: 1) {
                navButton(.new, id: "nav-new")
                navButton(.projects, id: "nav-projects")
                navButton(.artifacts, id: "nav-artifacts")
                navButton(.scheduled, id: "nav-scheduled")
                navButton(.customize, id: "nav-customize")
            }
            .padding(.horizontal, 10)
            .accessibilityLabel("Primary")

            if model.hasPinnedItems {
                pinnedSection
            }

            tasksSection

            Spacer()

            Button {
                accountOpen.toggle()
                languageOpen = false
            } label: {
                HStack(spacing: 10) {
                    if let logo = HandoffImage.coworkLogo(dark: model.theme == .dark, width: 28) {
                        logo.resizable().scaledToFit().frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "cat.fill")
                    }
                    Text("Yuzu Beta")
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                }
                .foregroundStyle(colors.muted)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityID("account-button")
            .accessibilityID("account-popover")
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
            .overlay(alignment: .bottomLeading) {
                if accountOpen {
                    accountPopover
                        .padding(.leading, 10)
                        .padding(.bottom, 52)
                }
            }
        }
        .background(colors.side)
        .dismissesOnEscape($accountOpen)
        .dismissesOnEscape($languageOpen)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(colors.line.opacity(0.5))
                .frame(width: 1)
        }
        .accessibilityID("sidebar")
    }

    private var accountPopover: some View {
        HandoffPopover(colors: colors) {
            HandoffMenuLabel(title: "Yuzu Beta Version 0.0.1", colors: colors)
            HandoffPopoverRow(title: "Settings", colors: colors) {
                accountOpen = false
                model.openSettings()
            }
            .accessibilityIdentifier("account-menu-settings")
            HandoffPopoverRow(
                title: model.interfaceLanguage == "English" ? "Language  ✓  English" : "Language",
                colors: colors
            ) {
                languageOpen.toggle()
            }
            if languageOpen {
                HandoffPopoverRow(title: "English  ✓", colors: colors) {
                    model.interfaceLanguage = "English"
                    languageOpen = false
                }
                .accessibilityIdentifier("account-language-english")
            }
            HandoffPopoverRow(title: "Inference configuration", colors: colors) {
                accountOpen = false
                model.openSettings(tab: .developer, anchor: .inference)
            }
            HandoffPopoverRow(title: "View changelog", colors: colors) {
                accountOpen = false
                model.changelogPresented = true
            }
            .accessibilityIdentifier("account-changelog")
            HandoffPopoverRow(title: "Learn more", colors: colors) {
                accountOpen = false
                if let url = URL(string: "https://github.com/adityachauhan0/yuzu") {
                    NSWorkspace.shared.open(url)
                }
            }
            .accessibilityIdentifier("account-learn-more")
            HandoffPopoverRow(title: "Sign out", colors: colors) {
                accountOpen = false
                model.showToast("Yuzu runs on this Mac. There is no account to sign out of.")
            }
            .accessibilityIdentifier("account-sign-out")
        }
        .frame(width: 260)
    }

    private var windowBar: some View {
        HStack(spacing: 12) {
            // The window's own traffic lights sit here; see `WindowChrome`.
            Color.clear
                .frame(width: WindowChrome.trafficLightsWidth, height: 14)
            Spacer()
            Button {
                model.sidebarCollapsed.toggle()
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(colors.muted)
            .accessibilityID("sidebar-toggle")

            Button {
                model.searchOpen = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(colors.muted)
            .accessibilityID("search-button")
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
    }

    private var pinnedSection: some View {
        let pinned = model.pinnedSessions
        return VStack(alignment: .leading, spacing: 0) {
            Text("Pinned")
                .font(.system(size: 14))
                .foregroundStyle(colors.dim)
                .padding(.bottom, 8)
            if model.workspaceMode == .code {
                let projects = pinned.reduce(into: [String]()) { list, task in
                    if !list.contains(task.projectPath) { list.append(task.projectPath) }
                }
                ForEach(projects, id: \.self) { project in
                    Text(model.workspaceLabel(project))
                        .font(.system(size: 12))
                        .foregroundStyle(colors.dim)
                        .padding(.leading, 3)
                        .padding(.top, 6)
                    ForEach(pinned.filter { $0.projectPath == project }) { task in
                        taskButton(task, id: "pinned-task")
                    }
                }
            } else {
                ForEach(pinned) { task in
                    taskButton(task, id: "pinned-task")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 27)
    }

    private func taskButton(_ task: SessionSummary, id: String) -> some View {
        let active = model.sessionID == task.id && (
            (task.surface == .code && model.workspaceMode == .code && model.codeThreadOpen)
                || (task.surface == .cowork && model.workspaceMode == .cowork && model.coworkDestination == .task)
        )
        return Button {
            model.openTask(task.id)
        } label: {
            HStack(spacing: 17) {
                Circle().fill(active ? colors.accent : colors.muted).frame(width: 7, height: 7)
                Text(task.displayTitle)
                    .font(YuzuFonts.interface(model.interfaceFont, size: 15))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 20)
            .padding(.trailing, 10)
            .padding(.vertical, 3)
            .frame(minHeight: 31)
            .background(active ? colors.selected : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(active ? colors.text : colors.muted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(task.displayTitle)
        .accessibilityID(id, label: task.displayTitle)
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Tasks")
                    .font(.system(size: 14))
                    .foregroundStyle(colors.dim)
                Spacer()
                Button {
                    if model.taskSessions.isEmpty {
                        model.showToast("Recent tasks appear here after you send one.")
                    } else {
                        model.openSettings(tab: .code)
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(colors.muted)
                .accessibilityID("task-settings")
            }
            .padding(.horizontal, 18)
            .padding(.top, 27)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if model.workspaceMode == .code {
                        ForEach(model.codeWorkspaceGroups, id: \.name) { group in
                            Text(group.name)
                                .font(.system(size: 12))
                                .foregroundStyle(colors.dim)
                                .padding(.leading, 20)
                                .padding(.top, 10)
                                .accessibilityID("code-workspace-\(group.name)")
                            ForEach(group.tasks) { task in
                                taskButton(task, id: "sidebar-task")
                            }
                        }
                    } else {
                        ForEach(model.taskSessions) { task in
                            taskButton(task, id: "sidebar-task")
                        }
                    }
                }
                .padding(.leading, 13)
                .padding(.trailing, 10)
            }
            .scrollIndicators(.never)
        }
    }

    private func navButton(_ destination: CoworkDestination, id: String) -> some View {
        let selected = model.workspaceMode == .cowork && model.coworkDestination == destination
        return Button {
            model.selectCowork(destination)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon(for: destination))
                    .frame(width: 17, height: 17)
                Text(destination.rawValue)
                    .font(YuzuFonts.interface(model.interfaceFont, size: 15.5))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selected ? colors.selected : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(selected ? colors.text : colors.muted)
        }
        .buttonStyle(.plain)
        .accessibilityID(id)
    }

    private func icon(for destination: CoworkDestination) -> String {
        switch destination {
        case .new: "plus"
        case .projects: "folder"
        case .artifacts: "doc"
        case .scheduled: "calendar"
        case .customize: "slider.horizontal.3"
        case .task: "bubble.left"
        }
    }
}

struct ModeSwitch: View {
    @EnvironmentObject private var model: AppModel
    let colors: ThemeColors
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 2) {
            modeButton(.cowork, id: "mode-switch-cowork")
            modeButton(.code, id: "mode-switch-code")
        }
        .padding(2)
        .background(colors.surface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .frame(height: 34)
    }

    private func modeButton(_ mode: WorkspaceMode, id: String) -> some View {
        let active = model.workspaceMode == mode
        return Button {
            if mode == .code {
                model.selectCode()
            } else {
                model.selectCowork(model.coworkDestination)
            }
        } label: {
            Text(mode.rawValue)
                .font(.system(size: 15))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(active ? colors.selected : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(active ? colors.text : colors.muted)
        }
        .buttonStyle(.plain)
        .accessibilityID(id)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
