import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    let colors: ThemeColors
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 9) {
                    Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 14, height: 14)
                    Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 14, height: 14)
                    Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25)).frame(width: 14, height: 14)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 54)

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

            Spacer()

            Button {
                model.openSettings()
            } label: {
                HStack {
                    Image(systemName: "cat.fill")
                    Text("Yuzu Beta")
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                }
                .foregroundStyle(colors.muted)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .background(colors.side)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(colors.line.opacity(0.5))
                .frame(width: 1)
        }
        .accessibilityID("sidebar")
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
