import SwiftUI
import YuzuHarness

struct RootShellView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let colors = ThemeColors(palette: model.theme.palette)
        GeometryReader { proxy in
            HStack(spacing: 0) {
                if !model.sidebarCollapsed {
                    SidebarView(colors: colors, reduceMotion: reduceMotion)
                        .frame(width: CGFloat(Tokens.sidebarWidth))
                }
                MainColumnView(
                    colors: colors,
                    reduceMotion: reduceMotion,
                    width: proxy.size.width - (model.sidebarCollapsed ? 0 : CGFloat(Tokens.sidebarWidth))
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
    @EnvironmentObject private var model: AppModel

    private let examples: [(title: String, description: String, time: String)] = [
        (
            "Daily briefing",
            "What needs your attention today across calendar, email, and messages.",
            "Weekdays at 8:00 AM"
        ),
        (
            "Inbox triage",
            "Categorize your inbox and draft replies to anything urgent.",
            "Weekdays at 8:00 AM"
        ),
        (
            "Meeting prep",
            "A short brief before each meeting on your calendar, covering attendees, context, and agenda.",
            "Weekdays at 8:00 AM"
        ),
        (
            "Weekly review",
            "A Friday summary of what happened this week.",
            "Every Friday at 4:00 PM"
        ),
        (
            "Content ideas",
            "Draft a few post ideas each week from the latest news in your industry.",
            "Every Monday at 9:00 AM"
        ),
        (
            "Monitor a topic",
            "Watch for news or mentions of a topic, competitor, or keyword.",
            "Daily at 9:00 AM"
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Scheduled tasks")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(colors.text)
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(colors.muted)
                        Text("Sort by Next run")
                            .font(.system(size: 14))
                            .foregroundStyle(colors.muted)
                        Text("New task")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(colors.text)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(colors.selected)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                Text("Run tasks on a schedule or whenever you need them. Type /schedule in any existing task to set one up.")
                    .font(.system(size: 17))
                    .foregroundStyle(colors.dim)
                    .padding(.top, 10)

                HStack(spacing: 12) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(colors.dim)
                    Text("Scheduled tasks only run while your computer is awake and online.")
                        .font(.system(size: 16))
                        .foregroundStyle(colors.text)
                    Spacer()
                    Button {
                        model.keepAwake.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sun.max")
                            Text("Keep awake")
                            RoundedRectangle(cornerRadius: 10)
                                .fill(model.keepAwake ? colors.accent : colors.line)
                                .frame(width: 36, height: 20)
                                .overlay(alignment: model.keepAwake ? .trailing : .leading) {
                                    Circle()
                                        .fill(colors.text)
                                        .frame(width: 16, height: 16)
                                        .padding(2)
                                }
                        }
                        .font(.system(size: 14))
                        .foregroundStyle(colors.text)
                    }
                    .buttonStyle(.plain)
                    .accessibilityID("awake-control")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(colors.surface.opacity(0.35))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(colors.line, lineWidth: 1))
                .padding(.top, 52)

                VStack(spacing: 8) {
                    Image(systemName: "stopwatch")
                        .font(.system(size: 48))
                        .foregroundStyle(colors.line)
                    Text("No scheduled tasks yet.")
                        .font(.system(size: 16))
                        .foregroundStyle(colors.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)

                Rectangle()
                    .fill(colors.line.opacity(0.4))
                    .frame(height: 1)
                    .padding(.top, 24)

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .leading,
                    spacing: 37
                ) {
                    ForEach(examples, id: \.title) { example in
                        scheduleExample(example)
                    }
                }
                .padding(.top, 72)
                .padding(.horizontal, 8)
            }
            .frame(maxWidth: 1152)
            .padding(.top, 65)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scheduleExample(_ example: (title: String, description: String, time: String)) -> some View {
        Button {} label: {
            HStack(alignment: .top, spacing: 19) {
                Image(systemName: icon(for: example.title))
                    .font(.system(size: 18))
                    .foregroundStyle(colors.muted)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 6) {
                    Text(example.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(colors.text)
                    Text(example.description)
                        .font(.system(size: 14))
                        .foregroundStyle(colors.dim)
                        .fixedSize(horizontal: false, vertical: true)
                    Label(example.time, systemImage: "clock")
                        .font(.system(size: 13))
                        .foregroundStyle(colors.dim)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 103, alignment: .topLeading)
        }
        .buttonStyle(.plain)
        .accessibilityID("schedule-example-\(example.title)")
    }

    private func icon(for title: String) -> String {
        switch title {
        case "Daily briefing": "sun.max"
        case "Inbox triage": "envelope"
        case "Meeting prep": "calendar"
        case "Weekly review": "list.bullet"
        case "Content ideas": "lightbulb"
        case "Monitor a topic": "binoculars"
        default: "calendar"
        }
    }
}
