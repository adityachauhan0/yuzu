import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    let colors: ThemeColors
    let reduceMotion: Bool

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

            Menu {
                Text("Yuzu Beta Version 0.0.1")
                Button("Settings") {
                    model.openSettings()
                }
                .accessibilityIdentifier("account-menu-settings")
                Button("Language") {}
                Button("Inference configuration") {
                    model.openSettings(tab: .developer)
                }
                Divider()
                Button("View changelog") {}
                Button("Learn more") {}
                Button("Sign out") {}
            } label: {
                HStack(spacing: 10) {
                    if let logo = HandoffImage.coworkLogo(dark: model.theme == .dark) {
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
            .menuStyle(.borderlessButton)
            .accessibilityID("account-button")
        }
        .background(colors.side)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(colors.line.opacity(0.5))
                .frame(width: 1)
        }
        .accessibilityID("sidebar")
    }

    private var windowBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 9) {
                Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 14, height: 14)
                Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 14, height: 14)
                Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25)).frame(width: 14, height: 14)
            }
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

            Button {} label: {
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Pinned")
                .font(.system(size: 14))
                .foregroundStyle(colors.dim)
                .padding(.horizontal, 18)
            // Pinned rows appear when sessions or projects are pinned.
        }
        .padding(.top, 27)
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Tasks")
                    .font(.system(size: 14))
                    .foregroundStyle(colors.dim)
                Spacer()
                Button {} label: {
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

            ForEach(model.recentTaskTitles, id: \.self) { title in
                Button {
                    model.selectCowork(.task)
                } label: {
                    HStack(spacing: 17) {
                        Circle().fill(colors.muted).frame(width: 7, height: 7)
                        Text(title)
                            .font(.system(size: 15))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.leading, 33)
                    .padding(.trailing, 10)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(colors.muted)
                .accessibilityID("sidebar-task")
            }
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
                    .font(.system(size: 15.5))
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
                model.selectCowork(model.coworkDestination == .task ? .new : model.coworkDestination)
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
