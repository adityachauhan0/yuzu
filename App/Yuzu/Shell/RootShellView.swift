import SwiftUI
import YuzuHarness

struct RootShellView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let colors = ThemeColors(palette: model.theme.palette)
        GeometryReader { proxy in
            HStack(spacing: 0) {
                SidebarView(colors: colors, reduceMotion: reduceMotion)
                    .frame(width: CGFloat(Tokens.sidebarWidth))
                MainColumnView(
                    colors: colors,
                    reduceMotion: reduceMotion,
                    width: proxy.size.width - CGFloat(Tokens.sidebarWidth)
                )
            }
            .background(colors.canvas)
            .overlay {
                if model.settingsPresented {
                    SettingsDialog(colors: colors)
                }
            }
            .onAppear { model.contentWidth = proxy.size.width }
            .onChange(of: proxy.size.width) { _, width in
                model.contentWidth = width
            }
        }
        .preferredColorScheme(model.theme == .dark ? .dark : .light)
    }
}

struct MainColumnView: View {
    @EnvironmentObject private var model: AppModel
    let colors: ThemeColors
    let reduceMotion: Bool
    let width: CGFloat

    var body: some View {
        ZStack {
            switch model.workspaceMode {
            case .code:
                CodeHomeView(colors: colors)
                    .accessibilityID("code-view")
            case .cowork:
                coworkContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.canvas)
    }

    @ViewBuilder
    private var coworkContent: some View {
        switch model.coworkDestination {
        case .new:
            CoworkHomeView(colors: colors)
                .accessibilityID("home")
        case .projects:
            EmptyPanelView(
                colors: colors,
                title: "No project yet",
                description: "Your project is ready for new tasks.",
                detail: "Choose a folder to start a task in this workspace."
            )
        case .artifacts:
            EmptyPanelView(
                colors: colors,
                title: "No artifacts yet",
                description: "Artifacts created from tasks will appear here.",
                detail: "Start a task to create an artifact in this workspace."
            )
        case .scheduled:
            ScheduledEmptyView(colors: colors)
        case .customize:
            CustomizeView(colors: colors)
        case .task:
            TaskThreadView(
                colors: colors,
                reduceMotion: reduceMotion,
                width: width
            )
            .accessibilityID("task-view")
        }
    }
}

struct EmptyPanelView: View {
    let colors: ThemeColors
    let title: String
    let description: String
    let detail: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            VStack(spacing: 8) {
                Text(title)
                    .font(.custom("Georgia", size: 28))
                    .foregroundStyle(colors.text)
                    .accessibilityID("panel-\(title)", label: title)
                Text(description)
                    .font(.system(size: 16))
                    .foregroundStyle(colors.muted)
                Text(detail)
                    .font(.system(size: 14))
                    .foregroundStyle(colors.dim)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: CGFloat(Tokens.contentWidth))
            Button("New task") {}
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(colors.selected)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ScheduledEmptyView: View {
    let colors: ThemeColors

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scheduled")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(colors.text)
            Text("No scheduled tasks yet.")
                .foregroundStyle(colors.muted)
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
