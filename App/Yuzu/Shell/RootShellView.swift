import AppKit
import SwiftUI
import YuzuHarness

struct RootShellView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let colors = ThemeColors(palette: model.theme.palette)
        let reduced = reduceMotion || model.motionSetting == "Reduced"
        GeometryReader { proxy in
            let compact = proxy.size.width <= 768
            let sidebarWidth: CGFloat = proxy.size.width <= 1024 ? 232 : CGFloat(Tokens.sidebarWidth)
            let sidebarShown = !model.sidebarCollapsed && !compact
            HStack(spacing: 0) {
                if sidebarShown {
                    SidebarView(colors: colors, reduceMotion: reduced)
                        .frame(width: sidebarWidth)
                }
                MainColumnView(
                    colors: colors,
                    reduceMotion: reduced,
                    width: proxy.size.width - (sidebarShown ? sidebarWidth : 0)
                )
            }
            .background(colors.canvas)
            .animation(MotionTiming.animation(reduceMotion: reduced, drawer: true), value: sidebarShown)
            .animation(MotionTiming.animation(reduceMotion: reduced, drawer: true), value: compact)
            .overlay(alignment: .topLeading) {
                if model.sidebarCollapsed {
                    Button {
                        model.sidebarCollapsed = false
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 14))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.yuzu)
                    .foregroundStyle(colors.muted)
                    .padding(.leading, WindowChrome.leading * 2 + WindowChrome.trafficLightsWidth)
                    .frame(height: WindowChrome.barHeight)
                    .accessibilityID("sidebar-reopen", label: "Show sidebar")
                }
            }
            .overlay(alignment: .leading) {
                if compact, !model.sidebarCollapsed {
                    SidebarView(colors: colors, reduceMotion: reduced)
                        .frame(width: min(270, max(200, proxy.size.width - 52)))
                        .shadow(color: .black.opacity(0.35), radius: 16, x: 8, y: 0)
                }
            }
            .onAppear {
                if compact { model.sidebarCollapsed = true }
            }
            .onChange(of: compact) { _, isCompact in
                model.sidebarCollapsed = isCompact
            }
            .overlay {
                if model.searchOpen {
                    SearchDialogView(colors: colors)
                }
            }
            .overlay {
                if model.settingsPresented {
                    SettingsDialog(colors: colors)
                }
            }
            .background(EscapeKeyMonitor { model.handleEscape() })
            .background(OutsideClickMonitor { model.outsideClicks.closeAll() })
            .overlay {
                if let request = model.pendingPermission {
                    PermissionAskView(colors: colors, request: request)
                }
            }
            .overlay {
                if model.changelogPresented {
                    ChangelogView(colors: colors)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let message = model.toastMessage {
                    HandoffToast(message: message, colors: colors)
                        .padding(.trailing, 26)
                        .padding(.bottom, 24)
                        .transition(.opacity)
                }
            }
            .onAppear { model.contentWidth = proxy.size.width }
            .onChange(of: proxy.size.width) { _, width in
                model.contentWidth = width
            }
        }
        .preferredColorScheme(model.theme == .dark ? .dark : model.theme == .light ? .light : nil)
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
                if model.codeThreadOpen {
                    TaskThreadView(
                        colors: colors,
                        reduceMotion: reduceMotion,
                        width: width
                    )
                    .accessibilityID("code-task-view")
                } else {
                    CodeHomeView(colors: colors)
                        .accessibilityID("code-view")
                }
            case .cowork:
                coworkContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.canvas)
        .animation(MotionTiming.animation(reduceMotion: reduceMotion), value: model.workspaceMode)
        .animation(MotionTiming.animation(reduceMotion: reduceMotion), value: model.coworkDestination)
    }

    @ViewBuilder
    private var coworkContent: some View {
        switch model.coworkDestination {
        case .new:
            CoworkHomeView(colors: colors)
                .accessibilityID("home")
        case .projects:
            ProjectsView(colors: colors)
                .accessibilityID("projects-view")
        case .artifacts:
            if !model.hasArtifacts {
                EmptyPanelView(
                    colors: colors,
                    title: "No artifacts yet",
                    description: "Artifacts created from tasks will appear here.",
                    detail: "Start a task to create an artifact in this workspace."
                )
            } else {
                ArtifactListView(colors: colors)
            }
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
    @EnvironmentObject private var model: AppModel
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
            Button("New task") {
                model.selectCowork(.new)
            }
                .buttonStyle(.yuzu)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(colors.selected)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ChangelogView: View {
    @EnvironmentObject private var model: AppModel
    let colors: ThemeColors

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { model.changelogPresented = false }
            VStack(alignment: .leading, spacing: 12) {
                Text("Yuzu Beta Version 0.0.1")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(colors.text)
                Text("Yuzu runs a local model through uzu. Weights stay in the uzu cache on this Mac.")
                    .font(.system(size: 15))
                    .foregroundStyle(colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Close") { model.changelogPresented = false }
                        .buttonStyle(.yuzu)
                        .foregroundStyle(colors.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(colors.surfaceHover)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.line, lineWidth: 1))
                        .accessibilityID("changelog-close")
                }
            }
            .padding(23)
            .frame(width: 500)
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(colors.line, lineWidth: 1))
            .accessibilityID("changelog-dialog")
        }
    }
}

struct ArtifactListView: View {
    @EnvironmentObject private var model: AppModel
    let colors: ThemeColors

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Artifacts")
                    .font(.custom("Georgia", size: 32))
                    .foregroundStyle(colors.text)
                ForEach(model.allArtifacts, id: \.path) { artifact in
                    let path = artifact.path
                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(colors.text)
                            Text(artifact.taskTitle)
                                .font(.system(size: 13))
                                .foregroundStyle(colors.dim)
                            if let kind = model.fileReviewRows.first(where: {
                                URL(fileURLWithPath: $0.path).lastPathComponent == URL(fileURLWithPath: path).lastPathComponent
                            })?.kind {
                                Text(kind)
                                    .font(.system(size: 13))
                                    .foregroundStyle(colors.dim)
                                    .accessibilityID("artifact-review-\(kind)")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.line, lineWidth: 1))
                    }
                    .buttonStyle(.yuzu)
                    .accessibilityID("artifact-\(URL(fileURLWithPath: path).lastPathComponent)")
                }
            }
            .frame(maxWidth: 806, alignment: .leading)
            .padding(40)
        }
        .scrollIndicators(.never)
    }
}

struct PermissionAskView: View {
    @EnvironmentObject private var model: AppModel
    let colors: ThemeColors
    let request: PermissionRequestRecord

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Text("Allow this?")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(colors.text)
                Text(request.toolName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(colors.text)
                Text(request.resources.joined(separator: "\n"))
                    .font(.system(size: 14))
                    .foregroundStyle(colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    permissionButton("Reject", id: "permission-reject") {
                        Task { await model.replyToPending(.reject) }
                    }
                    permissionButton("Once", id: "permission-once") {
                        Task { await model.replyToPending(.once) }
                    }
                    permissionButton("Always", id: "permission-always") {
                        Task { await model.replyToPending(.always) }
                    }
                }
                .padding(.top, 8)
            }
            .padding(22)
            .frame(width: 460)
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(colors.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
            .accessibilityID("permission-dialog")
        }
    }

    private func permissionButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.yuzu)
            .font(.system(size: 14))
            .foregroundStyle(colors.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(colors.surfaceHover)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.line, lineWidth: 1))
            .accessibilityID(id)
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
    @State private var dialogOpen = false
    @State private var draftName = ""
    @State private var draftPrompt = ""
    @State private var draftTime = ""

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
                    HStack(spacing: 8) {
                        Image(systemName: "sun.max")
                        Text("Keep awake")
                        YuzuSwitch(
                            colors: colors,
                            isOn: Binding(
                                get: { model.keepAwake },
                                set: { model.setKeepAwake($0) }
                            ),
                            accessibilityID: "awake-control"
                        )
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(colors.text)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(colors.surface.opacity(0.35))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(colors.line, lineWidth: 1))
                .padding(.top, 52)

                if visibleTasks.isEmpty {
                    VStack(spacing: 8) {
                        ScheduledStopwatchIllustration(dark: isDark)
                            .padding(.bottom, 14)
                        Text("No scheduled tasks yet.")
                            .font(.system(size: 16))
                            .foregroundStyle(colors.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 287)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(visibleTasks) { task in
                            scheduledRow(task)
                        }
                    }
                    .padding(.top, 28)
                }

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
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            model.reloadSchedules()
            consumeScheduleComposer()
        }
        .dismissesOnEscape($sortMenuOpen)
        .dismissesOnOutsideClick($sortMenuOpen)
        .dismissesOnEscape($newMenuOpen)
        .dismissesOnOutsideClick($newMenuOpen)
        .dismissesOnEscape($dialogOpen)
        .dismissesOnEscape(when: searchVisible) {
            searchVisible = false
            searchQuery = ""
        }
        .onChange(of: model.scheduleComposerOpen) { _, _ in
            consumeScheduleComposer()
        }
        .overlay {
            if dialogOpen {
                scheduleDialog
            }
        }
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
                .buttonStyle(.yuzu)
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
                .buttonStyle(.yuzu)
                .popupChrome()
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
                    .foregroundStyle(colors.onAccent)
                    .padding(.horizontal, 13)
                    .frame(minWidth: 126, minHeight: 38)
                    .background(colors.softText)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.yuzu)
                .popupChrome()
                .accessibilityID("scheduled-new-button")
            }
            .padding(.top, 3)

            if searchVisible {
                TextField("Search scheduled tasks", text: $searchQuery)
                    .textFieldStyle(.plain).yuzuFieldHover()
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
                        openScheduleDialog(name: "", prompt: "", time: "")
                    }
                    .buttonStyle(.yuzu)
                    .accessibilityID("create-schedule-option")
                    Button("New task") {
                        newMenuOpen = false
                        model.selectCowork(.new)
                    }
                    .buttonStyle(.yuzu)
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
        .buttonStyle(.yuzu)
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
        .popupChrome()
    }

    private func scheduleExample(_ example: (title: String, description: String, time: String)) -> some View {
        Button {
            openScheduleDialog(name: example.title, prompt: example.description, time: example.time)
        } label: {
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
        .buttonStyle(.yuzu)
        .accessibilityID("schedule-example-\(example.title)")
    }

    private var visibleTasks: [ScheduledTaskRecord] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = model.scheduledTasks.filter { task in
            query.isEmpty
                || task.name.localizedCaseInsensitiveContains(query)
                || task.prompt.localizedCaseInsensitiveContains(query)
        }
        if sortLabel == "Name" {
            return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return filtered.sorted { $0.nextRun < $1.nextRun }
    }

    private func consumeScheduleComposer() {
        guard model.scheduleComposerOpen else { return }
        openScheduleDialog(
            name: "",
            prompt: model.scheduleComposerPrompt,
            time: model.scheduleComposerTime
        )
        model.scheduleComposerOpen = false
    }

    private func openScheduleDialog(name: String, prompt: String, time: String) {
        draftName = name
        draftPrompt = prompt
        draftTime = time
        dialogOpen = true
    }

    private func scheduledRow(_ task: ScheduledTaskRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.name)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(colors.text)
            Text("\(task.scheduleText) · \(task.nextRun.formatted(date: .abbreviated, time: .shortened))")
                .font(.system(size: 14))
                .foregroundStyle(colors.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.line, lineWidth: 1))
        .accessibilityID("scheduled-task-\(task.name)")
    }

    private var scheduleDialog: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { dialogOpen = false }
            VStack(alignment: .leading, spacing: 0) {
                Text("New scheduled task")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(colors.text)
                    .padding(.bottom, 16)
                    .accessibilityID("schedule-dialog-title")
                scheduleField("Task name", text: $draftName, axis: nil)
                    .accessibilityID("schedule-name")
                scheduleField("What should it do?", text: $draftPrompt, axis: .vertical)
                    .accessibilityID("schedule-prompt")
                scheduleField("Schedule", text: $draftTime, axis: nil)
                    .accessibilityID("schedule-time")
                HStack {
                    Spacer()
                    Button("Cancel") { dialogOpen = false }
                        .buttonStyle(.yuzu)
                        .foregroundStyle(colors.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(colors.surfaceHover)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.line, lineWidth: 1))
                        .accessibilityID("schedule-cancel")
                    Button("Create task") {
                        do {
                            try model.createScheduledTask(name: draftName, prompt: draftPrompt, scheduleText: draftTime)
                            dialogOpen = false
                        } catch {
                            model.showToast("Use a time like Weekdays at 8:00 AM.")
                        }
                    }
                    .buttonStyle(.yuzu)
                    .foregroundStyle(colors.onAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(colors.softText)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityID("schedule-create")
                }
                .padding(.top, 20)
            }
            .padding(22)
            .frame(width: 460)
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(colors.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
            .accessibilityID("schedule-dialog")
        }
    }

    private func scheduleField(_ title: String, text: Binding<String>, axis: Axis?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(colors.text)
            if axis == .vertical {
                TextField("", text: text, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.plain).yuzuFieldHover()
                    .padding(10)
                    .background(colors.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.line, lineWidth: 1))
            } else {
                TextField(title == "Schedule" ? "Weekdays at 8:00 AM" : "", text: text)
                    .textFieldStyle(.plain).yuzuFieldHover()
                    .padding(10)
                    .background(colors.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.line, lineWidth: 1))
            }
        }
        .padding(.top, 11)
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
