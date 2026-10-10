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

    private var isDark: Bool { model.theme == .dark }
    @State private var searchVisible = false
    @State private var searchQuery = ""
    @State private var sortLabel = "Next run"
    @State private var sortMenuOpen = false
    @State private var newMenuOpen = false

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
                HStack(alignment: .top) {
                    Text("Scheduled tasks")
                        .font(.custom("Georgia", size: 32))
                        .foregroundStyle(colors.text)
                    Spacer()
                    scheduledControls
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
                    ScheduledStopwatchIllustration(dark: isDark)
                        .padding(.bottom, 14)
                    Text("No scheduled tasks yet.")
                        .font(.system(size: 16))
                        .foregroundStyle(colors.muted)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 287)

                ScheduledWaveDivider(dark: isDark)
                    .padding(.top, 0)

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

    private var scheduledControls: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 10) {
                Button {
                    searchVisible.toggle()
                    if !searchVisible { searchQuery = "" }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .frame(width: 35, height: 37)
                }
                .buttonStyle(.plain)
                .foregroundStyle(colors.muted)
                .background(searchVisible ? colors.selected : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityID("scheduled-search-button")

                Button {
                    sortMenuOpen.toggle()
                    newMenuOpen = false
                } label: {
                    HStack(spacing: 8) {
                        Text("Sort by")
                        Text(sortLabel)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                    }
                    .font(.system(size: 16))
                    .foregroundStyle(sortMenuOpen ? colors.text : colors.muted)
                    .padding(.horizontal, 13)
                    .frame(minWidth: 182, minHeight: 38)
                    .background(colors.selected)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityID("scheduled-sort-button")

                Button {
                    newMenuOpen.toggle()
                    sortMenuOpen = false
                } label: {
                    HStack(spacing: 8) {
                        Text("New task")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(red: 0.11, green: 0.11, blue: 0.13))
                    .padding(.horizontal, 13)
                    .frame(minWidth: 126, minHeight: 38)
                    .background(Color(red: 0.94, green: 0.95, blue: 0.95))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityID("scheduled-new-button")
            }
            .padding(.top, 3)

            if searchVisible {
                TextField("Search scheduled tasks", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(width: 340)
                    .background(colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(colors.line, lineWidth: 1))
                    .padding(.top, 45)
                    .accessibilityID("scheduled-search-field")
            }

            if sortMenuOpen {
                scheduledPopover {
                    sortOption("Next run")
                    sortOption("Name")
                }
                .padding(.top, 45)
                .padding(.trailing, 137)
            }

            if newMenuOpen {
                scheduledPopover {
                    Button("Create scheduled task") {
                        newMenuOpen = false
                    }
                    .buttonStyle(.plain)
                    .accessibilityID("create-schedule-option")
                    Button("New task") {
                        newMenuOpen = false
                        model.selectCowork(.new)
                    }
                    .buttonStyle(.plain)
                    .accessibilityID("new-regular-task-option")
                }
                .padding(.top, 45)
            }
        }
    }

    private func sortOption(_ label: String) -> some View {
        Button {
            sortLabel = label
            sortMenuOpen = false
        } label: {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(colors.text)
        .accessibilityIdentifier("scheduled-sort-\(label)")
    }

    private func scheduledPopover<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            content()
        }
        .padding(6)
        .frame(minWidth: 200)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
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
