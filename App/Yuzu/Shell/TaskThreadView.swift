import AppKit
import SwiftUI
import YuzuHarness

struct TaskThreadView: View {
    @EnvironmentObject private var model: AppModel
    let colors: ThemeColors
    let reduceMotion: Bool
    let width: CGFloat
    @State private var renameOpen = false
    @State private var renameDraft = ""
    @State private var titleMenuOpen = false
    @State private var addMenuOpen = false
    @State private var modelMenuOpen = false
    @State private var effortMenuOpen = false
    @State private var agentMenuOpen = false
    @State private var attachments: [String] = []
    @State private var questionAnswers: [String: String] = [:]
    @State private var claimedThreadPrompt = false
    @State private var threadPrompt = 0
    @ObservedObject private var machine = MachineMonitor.shared

    private var presentation: InspectorPresentation {
        model.inspectorPresentation(width: model.contentWidth)
    }

    private var isDark: Bool { model.isDarkAppearance }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                threadColumn
                if presentation == .beside, model.inspectorOpen {
                    inspectorPanel
                        .frame(width: 376)
                        .padding(.top, 9)
                        .padding(.leading, 4)
                        .padding(.trailing, 10)
                }
            }
            if presentation == .overlay, model.inspectorOpen {
                inspectorPanel
                    .frame(width: min(376, width - 20))
                    .padding(.top, 60)
                    .padding(.trailing, 10)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            if renameOpen {
                renameDialog
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityID("inspector-layout-\(presentation.rawValue)")
        .animation(MotionTiming.animation(reduceMotion: reduceMotion, drawer: true), value: model.inspectorOpen)
        .dismissesOnEscape($titleMenuOpen)
        .dismissesOnOutsideClick($titleMenuOpen)
        .dismissesOnEscape($addMenuOpen)
        .dismissesOnOutsideClick($addMenuOpen)
        .dismissesOnEscape($modelMenuOpen)
        .dismissesOnOutsideClick($modelMenuOpen)
        .dismissesOnEscape($effortMenuOpen)
        .dismissesOnOutsideClick($effortMenuOpen)
        .dismissesOnEscape($agentMenuOpen)
        .dismissesOnOutsideClick($agentMenuOpen)
        .dismissesOnEscape($renameOpen)
        .sheet(isPresented: Binding(
            get: { model.childTranscriptSessionID != nil },
            set: { if !$0 { model.childTranscriptSessionID = nil } }
        )) {
            if let sessionID = model.childTranscriptSessionID {
                ChildTranscriptSheet(sessionID: sessionID, colors: colors)
                    .environmentObject(model)
            }
        }
    }

    // MARK: Thread

    private var threadColumn: some View {
        VStack(spacing: 0) {
            threadTop
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        let items = filteredThreadItems(
                            ThreadItem.build(model.transcript, events: model.threadHarnessEvents)
                        )
                        let lastUserIndex = items.lastIndex(where: {
                            if case .user = $0 { return true }
                            return false
                        })
                        let lastThoughtIndex = items.lastIndex(where: {
                            if case .thought = $0 { return true }
                            return false
                        })
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            threadItem(
                                item,
                                index: index,
                                isLast: index == items.count - 1,
                                isLatestUser: index == lastUserIndex,
                                streamThought: model.turnRunning && index == lastThoughtIndex
                            )
                        }
                        if model.awaitingAssistantText {
                            ThinkingLine(colors: colors, reduceMotion: reduceMotion)
                        }
                        ForEach(model.pendingQuestions, id: \.callID) { pending in
                            questionCard(pending)
                        }
                        Color.clear.frame(height: 1).id("thread-end")
                    }
                    .frame(maxWidth: min(900, model.transcriptColumnMax), alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 44)
                    .padding(.bottom, 72)
                }
                .scrollIndicators(.never)
                .onChange(of: model.transcript) { _, _ in
                    proxy.scrollTo("thread-end", anchor: .bottom)
                }
                .onAppear {
                    model.reloadTranscript()
                    proxy.scrollTo("thread-end", anchor: .bottom)
                }
            }
            threadBottom
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            claimThreadPrompt()
            machine.start()
        }
        .onChange(of: model.sessionID) { _, _ in
            threadPrompt = PhraseVisits.claim(.threadPrompt)
            claimedThreadPrompt = true
        }
    }

    private func claimThreadPrompt() {
        guard !claimedThreadPrompt else { return }
        threadPrompt = PhraseVisits.claim(.threadPrompt)
        claimedThreadPrompt = true
    }

    /// When the sidebar is closed, the real traffic lights occupy the top-left of this column.
    /// Extra room between the sidebar and the composer when the progress panel is also open.
    private var composerSideInset: CGFloat {
        presentation == .beside && model.inspectorOpen ? 28 : 16
    }

    private var threadHeaderLeading: CGFloat {
        guard model.sidebarCollapsed else { return 22 }
        return WindowChrome.leading * 2 + WindowChrome.trafficLightsWidth + 28 + 16
    }

    private var threadTop: some View {
        HStack {
            Button {
                titleMenuOpen.toggle()
            } label: {
                HStack(spacing: 9) {
                    Text(model.taskTitle)
                        .font(YuzuFonts.interface(model.interfaceFont, size: 17))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11))
                }
                .frame(minHeight: 44)
                .foregroundStyle(colors.text)
            }
            .buttonStyle(.yuzu)
            .popupChrome()
            .accessibilityID("thread-title")
            TextField("Find in thread", text: $model.threadFindQuery)
                .textFieldStyle(.plain).yuzuFieldHover()
                .font(.system(size: 14))
                .frame(maxWidth: 180)
                .accessibilityID("thread-find")
            Spacer()
            Button {
                model.inspectorOpen.toggle()
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 14))
                    .frame(width: 36, height: 36)
                    .background(model.inspectorOpen ? colors.toggleOn : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(model.inspectorOpen ? colors.toggleOnText : colors.muted)
            }
            .buttonStyle(.yuzu)
            .accessibilityID("thread-layout", label: "Toggle task details")
        }
        .padding(.leading, threadHeaderLeading)
        .padding(.trailing, 22)
        .frame(height: WindowChrome.barHeight)
        .animation(MotionTiming.animation(reduceMotion: reduceMotion, drawer: true), value: model.sidebarCollapsed)
        .overlay(alignment: .topLeading) {
            if titleMenuOpen {
                HandoffPopover(colors: colors) {
                    HandoffMenuLabel(title: "Tasks", colors: colors)
                    titleRow("Rename", id: "thread-menu-rename") {
                        renameDraft = model.taskTitle
                        renameOpen = true
                    }
                    titleRow(model.taskPinned ? "Unpin" : "Pin", id: "thread-menu-pin") { model.togglePinCurrentTask() }
                    titleRow("Normal", id: "thread-menu-normal", checked: model.transcriptView == "Normal") {
                        model.transcriptView = "Normal"
                    }
                    titleRow("Thinking", id: "thread-menu-thinking", checked: model.transcriptView == "Thinking") {
                        model.transcriptView = "Thinking"
                    }
                    titleRow("Verbose", id: "thread-menu-verbose", checked: model.transcriptView == "Verbose") {
                        model.transcriptView = "Verbose"
                    }
                    titleRow("Delete", id: "thread-menu-delete") { model.deleteCurrentTask() }
                }
                .frame(width: 220)
                .padding(.top, 54)
                .padding(.leading, 18)
            }
        }
        .zIndex(2)
    }

    private func titleRow(_ title: String, id: String, checked: Bool = false, action: @escaping () -> Void) -> some View {
        HandoffPopoverRow(title: checked ? "\(title)  ✓" : title, colors: colors) {
            titleMenuOpen = false
            action()
        }
        .accessibilityID(id)
    }

    @ViewBuilder
    private func threadItem(
        _ item: ThreadItem,
        index: Int,
        isLast: Bool,
        isLatestUser: Bool,
        streamThought: Bool = false
    ) -> some View {
        switch item {
        case .user(let text):
            VStack(alignment: .trailing, spacing: 8) {
                Text(text)
                    .font(YuzuFonts.interface(model.interfaceFont, size: model.transcriptFontSize + 1))
                    .lineSpacing(5)
                    .foregroundStyle(colors.softText)
                    .textSelection(.enabled)
                    .padding(.vertical, 13)
                    .padding(.horizontal, 19)
                    .background(colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 18)
                    .padding(.leading, 80)
                if isLatestUser, !model.turnRunning {
                    Button("Revert") {
                        Task { await model.revertLastTurn() }
                    }
                    .buttonStyle(.yuzu)
                    .font(.system(size: 14))
                    .foregroundStyle(colors.dim)
                    .padding(.trailing, 24)
                    .accessibilityID("thread-revert")
                }
            }
            .padding(.top, index == 0 ? 0 : 48)
            .accessibilityID("thread-user")
        case .thought(let reasoning):
            ThreadThoughtRow(colors: colors, text: reasoning, streaming: streamThought)
                .padding(.top, index == 0 ? 0 : 20)
        case .tools(let label, let rows):
            ThreadToolGroupView(
                colors: colors,
                label: label,
                rows: rows,
                onOpenTask: { call in
                    if let child = model.childSessionID(forTaskCall: call.id) {
                        model.childTranscriptSessionID = child
                    }
                }
            )
            .padding(.top, index == 0 ? 0 : 20)
        case .compaction:
            Text("Earlier context was summarized.")
                .font(.system(size: 15))
                .foregroundStyle(colors.dim)
                .padding(.top, index == 0 ? 0 : 16)
                .accessibilityID("thread-compaction")
        case .reply(let text):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(FencedText.segments(text).enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .prose(let prose):
                        MarkdownProse(
                            text: prose,
                            font: replyFont(size: model.transcriptFontSize + 4),
                            colors: colors
                        )
                    case .code(let code):
                        CodeBlockView(
                            code: code,
                            theme: model.activeCodeTheme(dark: isDark),
                            codeFont: model.codeFont,
                            size: model.transcriptFontSize - 2
                        )
                        .padding(.vertical, 6)
                    }
                }
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        model.showToast("Copied response.")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 13))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.yuzu)
                    .foregroundStyle(colors.dim)
                    .padding(.top, 12)
                    .padding(.leading, -6)
                    .accessibilityID("thread-copy", label: "Copy response")
                }
            }
            .padding(.top, index == 0 ? 0 : 12)
            .accessibilityID("thread-reply")
        }
    }

    private func filteredThreadItems(_ items: [ThreadItem]) -> [ThreadItem] {
        let term = model.threadFindQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return items }
        return items.filter { item in
            switch item {
            case .user(let text), .reply(let text), .thought(let text):
                return text.lowercased().contains(term)
            case .tools(_, let rows):
                return rows.contains {
                    $0.result.lowercased().contains(term)
                        || $0.presentation.detail.lowercased().contains(term)
                }
            case .compaction:
                return "summarized".contains(term)
            }
        }
    }

    private func questionCard(_ pending: (callID: String, question: String)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pending.question)
                .font(.system(size: 16))
                .foregroundStyle(colors.text)
            TextField("Your answer", text: Binding(
                get: { questionAnswers[pending.callID, default: ""] },
                set: { questionAnswers[pending.callID] = $0 }
            ))
            .textFieldStyle(.plain).yuzuFieldHover()
            .padding(10)
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Button("Send answer") {
                let answer = questionAnswers[pending.callID, default: ""]
                Task { await model.answerPendingQuestion(callID: pending.callID, answer: answer) }
            }
            .buttonStyle(.yuzu)
            .foregroundStyle(colors.accent)
        }
        .padding(16)
        .background(colors.preview)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.top, 16)
        .accessibilityID("thread-question")
    }

    private func replyFont(size: CGFloat) -> Font {
        YuzuFonts.chat(model.chatFont, size: size)
    }

    private var threadBottom: some View {
        let ready = !model.threadDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                TextField(PhraseBook.line(.threadPrompt, index: threadPrompt), text: $model.threadDraft, axis: .vertical)
                    .textFieldStyle(.plain).yuzuFieldHover()
                    .font(YuzuFonts.interface(model.interfaceFont, size: 17))
                    .foregroundStyle(colors.text)
                    .lineLimit(2...7)
                    .padding(.horizontal, 23)
                    .padding(.top, 20)
                    .padding(.bottom, 4)
                    .frame(minHeight: 65, alignment: .top)
                    .onKeyPress { press in
                        guard press.key == .return, !press.modifiers.contains(.shift) else { return .ignored }
                        send()
                        return .handled
                    }
                    .accessibilityID("thread-input", label: PhraseBook.line(.threadPrompt, index: threadPrompt))
                HStack(spacing: 14) {
                    Button {
                        addMenuOpen.toggle()
                        modelMenuOpen = false
                    } label: {
                        Image(systemName: "plus").font(.system(size: 19)).frame(width: 28, height: 32)
                    }
                    .buttonStyle(.yuzu)
                    .popupChrome()
                    .foregroundStyle(colors.softText)
                    .accessibilityID("thread-add", label: "Add to message")
                    Button(action: chooseProject) {
                        Image(systemName: "folder.badge.plus").font(.system(size: 16)).frame(width: 28, height: 32)
                    }
                    .buttonStyle(.yuzu)
                    .foregroundStyle(colors.softText)
                    .accessibilityID("thread-project", label: "Add a project")
                    Spacer()
                    Button {
                        agentMenuOpen.toggle()
                        modelMenuOpen = false
                        effortMenuOpen = false
                    } label: {
                        Text(model.sessionAgentID == "plan" ? "Plan" : "Build")
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.yuzu)
                    .popupChrome()
                    .foregroundStyle(colors.softText)
                    .accessibilityID("thread-agent-button")
                    Button {
                        if model.needsModelDownload {
                            model.downloadModel()
                            return
                        }
                        modelMenuOpen.toggle()
                        effortMenuOpen = false
                        addMenuOpen = false
                    } label: {
                        Text(model.modelDisplayName).font(.system(size: 16)).lineLimit(1)
                    }
                    .buttonStyle(.yuzu)
                    .popupChrome()
                    .foregroundStyle(colors.softText)
                    .accessibilityID("thread-model-button")
                    Button {
                        effortMenuOpen.toggle()
                        modelMenuOpen = false
                        addMenuOpen = false
                    } label: {
                        Text(model.coworkEffortLabel)
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.yuzu)
                    .popupChrome()
                    .foregroundStyle(colors.subtle)
                    .accessibilityID("thread-effort")
                    .accessibilityID("thread-effort-button")
                    if model.turnRunning, !ready {
                        Button {
                            Task { await model.stopTurn() }
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 13))
                                .frame(width: 37, height: 37)
                                .background(colors.accent)
                                .foregroundStyle(colors.onAccent)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.yuzu)
                        .padding(.leading, 10)
                        .accessibilityID("stop-turn", label: "Stop")
                    } else {
                        Button(action: send) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 37, height: 37)
                                .background(ready ? colors.accent : colors.sendIdle)
                                .foregroundStyle(ready ? colors.onAccent : colors.sendIdleText)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.yuzu)
                        .padding(.leading, 10)
                        .accessibilityID(ready ? "thread-send-ready" : "thread-send", label: "Send message")
                    }
                }
                .padding(.leading, 20)
                .padding(.trailing, 18)
                .padding(.bottom, 10)
                .frame(minHeight: 51)
            }
            .frame(minHeight: 118)
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(colors.line, lineWidth: 1))
            .overlay(alignment: .bottomLeading) {
                if addMenuOpen {
                    HandoffPopover(colors: colors) {
                        HandoffMenuLabel(title: "Add to message", colors: colors)
                        HandoffPopoverRow(title: "Attach a file", colors: colors) {
                            addMenuOpen = false
                            attachFile()
                        }
                        .accessibilityID("thread-attach-file")
                        HandoffPopoverRow(title: "Choose a project", colors: colors) {
                            addMenuOpen = false
                            chooseProject()
                        }
                        .accessibilityID("thread-choose-project")
                    }
                    .frame(width: 220)
                    .padding(.bottom, 56)
                    .padding(.leading, 16)
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
                    .frame(width: 240)
                    .padding(.bottom, 56)
                    .padding(.trailing, 120)
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
                    .frame(width: 180)
                    .padding(.bottom, 56)
                    .padding(.trailing, 57)
                }
                if agentMenuOpen {
                    HandoffPopover(colors: colors) {
                        HandoffMenuLabel(title: "Agent", colors: colors)
                        HandoffPopoverRow(title: "Build", colors: colors) {
                            Task { await model.setSessionAgent("build") }
                            agentMenuOpen = false
                        }
                        HandoffPopoverRow(title: "Plan", colors: colors) {
                            Task { await model.setSessionAgent("plan") }
                            agentMenuOpen = false
                        }
                    }
                    .frame(width: 180)
                    .padding(.bottom, 56)
                    .padding(.trailing, 200)
                }
            }

            HStack {
                Text(model.threadContextUsageLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(colors.dim)
                    .accessibilityID("thread-context-usage")
                    .accessibilityID("thread-context-percent")
                Spacer()
                Text(model.speedLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(colors.dim)
                    .accessibilityID("thread-speed")
            }
            .padding(.horizontal, 4)
            .padding(.top, 6)

            if !attachments.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(attachments, id: \.self) { path in
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.system(size: 13))
                            .foregroundStyle(colors.dim)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
                .padding(.leading, 23)
                .accessibilityID("thread-attachments")
            }

            Text(AppModel.disclaimer)
                .font(.system(size: 13))
                .foregroundStyle(colors.dim)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .accessibilityID("task-disclaimer", label: AppModel.disclaimer)
        }
        .frame(maxWidth: 920)
        .padding(.horizontal, composerSideInset)
        .padding(.bottom, 7)
        .zIndex(1)
    }

    private func send() {
        let body = ComposerContext.prompt(model.threadDraft, attachments: attachments)
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.threadDraft = ""
        attachments = []
        Task { await model.sendPrompt(body) }
    }

    private func attachFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            attachments.append(contentsOf: panel.urls.map(\.path).filter { !attachments.contains($0) })
        }
    }

    private func chooseProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, !attachments.contains(url.path) {
            attachments.append(url.path)
        }
    }

    // MARK: Inspector

    private var inspectorPanel: some View {
        let folder = URL(fileURLWithPath: model.workspaceProjectPath).lastPathComponent
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                InspectorSection(title: "Progress", colors: colors) {
                    progressBody
                }
                InspectorSection(title: "Review", colors: colors) {
                    ForEach(model.fileReviewRows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(row.path)
                                    .font(.system(size: 14))
                                    .foregroundStyle(colors.muted)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(row.kind)
                                    .font(.system(size: 13))
                                    .foregroundStyle(colors.dim)
                                    .accessibilityID("review-row-\(row.kind)")
                                    .accessibilityID("artifact-review-\(row.kind)")
                            }
                            if !row.preview.isEmpty {
                                Text(row.preview)
                                    .font(YuzuFonts.code(model.codeFont, size: 12))
                                    .foregroundStyle(colors.muted)
                                    .lineLimit(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, 15)
                        .padding(.vertical, 4)
                    }
                    if model.fileReviewRows.isEmpty {
                        helpLine("Writes and edits from this task appear here.")
                            .padding(.top, 2)
                    }
                }
                InspectorSection(
                    title: folder.isEmpty ? "Project" : folder,
                    colors: colors,
                    trailing: AnyView(
                        Button {
                            let path = model.workspaceProjectPath
                            guard !path.isEmpty else { return }
                            NSWorkspace.shared.open(URL(fileURLWithPath: path))
                        } label: {
                            Image(systemName: "folder").font(.system(size: 15)).frame(width: 32, height: 32)
                        }
                        .buttonStyle(.yuzu)
                        .foregroundStyle(colors.subtle)
                        .padding(.trailing, 13)
                        .accessibilityID("inspector-open-folder", label: "Open \(folder) project")
                    )
                ) {
                    ForEach(model.createdArtifactPaths, id: \.self) { path in
                        fileRow(path)
                    }
                    helpLine("View and open files created during this task.")
                        .padding(.top, 2)
                        .padding(.bottom, 5)
                }
                InspectorSection(title: "Context", colors: colors) {
                    ForEach(model.referencedFiles, id: \.self) { path in
                        fileRow(path)
                    }
                    if !model.referencedToolNames.isEmpty {
                        Text(model.referencedToolNames.joined(separator: " · "))
                            .font(.system(size: 14))
                            .foregroundStyle(colors.muted)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 6)
                            .accessibilityID("inspector-tools")
                    }
                    helpLine("Track tools and referenced files used in this task.")
                        .padding(.top, 2)
                        .padding(.bottom, 5)
                }
            }
        }
        .scrollIndicators(.never)
        .frame(maxHeight: 480)
        .fixedSize(horizontal: false, vertical: true)
        .background(colors.preview)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.surfaceHover, lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 14, y: 8)
        .accessibilityIdentifier("thread-inspector")
    }

    private var progressBody: some View {
        let steps = model.taskSteps
        return VStack(alignment: .leading, spacing: 10) {
            TaskProgressBar(fraction: model.taskProgressFraction, colors: colors)
                .padding(.horizontal, 15)
                .padding(.top, 16)
                .accessibilityID("task-progress-bar", label: model.taskProgressLabel)
            Text(model.taskProgressLabel)
                .font(.system(size: 13))
                .foregroundStyle(colors.dim)
                .padding(.horizontal, 15)
            progressMarks
            if steps.isEmpty {
                helpLine("Progress on longer tasks appears here.")
                    .padding(.top, 8)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(steps.prefix(8))) { step in
                        Text(step.title)
                            .font(.system(size: 14))
                            .strikethrough(step.status == .completed)
                            .foregroundStyle(step.status == .inProgress ? colors.text : colors.dim)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 15)
                .padding(.top, 4)
                .accessibilityID("inspector-todos")
            }
            MachineMeters(sample: machine.sample, modelName: model.modelDisplayName, colors: colors)
                .padding(.horizontal, 15)
                .padding(.top, 6)
                .padding(.bottom, 12)
        }
    }

    private var progressMarks: some View {
        let shown = Array(model.taskSteps.prefix(6))
        return HStack(spacing: 0) {
            if shown.isEmpty {
                stepMark(.pending)
            } else {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Rectangle().fill(colors.dim).frame(width: 12, height: 1)
                    }
                    stepMark(item.status)
                }
            }
        }
        .padding(.horizontal, 17)
        .padding(.top, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.taskProgressLabel)
    }

    private func stepMark(_ status: TodoItem.Status) -> some View {
        ZStack {
            Circle()
                .fill(status == .completed ? colors.surfaceHover : status == .inProgress ? colors.accent.opacity(0.35) : Color.clear)
            Circle()
                .stroke(status == .inProgress ? colors.accent : colors.stepBorder, lineWidth: 1)
            if status == .completed {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(colors.dim)
            }
        }
        .frame(width: 32, height: 32)
    }

    private func helpLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(colors.dim)
            .lineSpacing(3)
            .padding(.horizontal, 15)
            .padding(.bottom, 10)
    }

    private func fileRow(_ path: String) -> some View {
        let url = model.resolvedProjectURL(path)
        return Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc")
                    .font(.system(size: 14))
                    .frame(width: 30, height: 30)
                    .background(colors.surfaceHover)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .foregroundStyle(colors.subtle)
                (Text(url.lastPathComponent).foregroundColor(colors.muted)
                    + Text(" · \(url.deletingLastPathComponent().lastPathComponent)").foregroundColor(colors.dim))
                    .font(.system(size: 15))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.yuzu)
        .padding(.horizontal, 15)
        .accessibilityID("inspector-file")
    }

    private var renameDialog: some View {
        ZStack {
            Color.black.opacity(0.4)
                .onTapGesture { renameOpen = false }
            VStack(alignment: .leading, spacing: 12) {
                Text("Rename")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(colors.text)
                TextField("Task", text: $renameDraft)
                    .textFieldStyle(.plain).yuzuFieldHover()
                    .padding(10)
                    .background(colors.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.line, lineWidth: 1))
                    .onSubmit(saveRename)
                HStack {
                    Spacer()
                    Button("Cancel") { renameOpen = false }
                        .buttonStyle(.yuzu)
                    Button("Save", action: saveRename)
                        .buttonStyle(.yuzu)
                        .accessibilityID("thread-rename-save")
                }
            }
            .padding(22)
            .frame(width: 420)
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func saveRename() {
        model.renameCurrentTask(renameDraft)
        renameOpen = false
    }
}

/// `.inspector-section`: a heading that folds its body, a rule between sections.
private struct InspectorSection<Content: View>: View {
    let title: String
    let colors: ThemeColors
    var trailing: AnyView?
    @ViewBuilder var content: () -> Content
    @State private var open = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    open.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 16))
                            .foregroundStyle(colors.text)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(colors.subtle)
                            .rotationEffect(.degrees(open ? 0 : -90))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 8)
                    .frame(minHeight: 45)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.yuzu)
                if let trailing { trailing }
            }
            if open {
                content()
            }
        }
        .overlay(alignment: .top) {
            Rectangle().fill(colors.selected).frame(height: 1)
        }
    }
}

/// Attached files and folders travel as plain lines after the prompt; the model reads them with its tools.
enum ComposerContext {
    static func prompt(_ text: String, attachments: [String]) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = attachments.map { path -> String in
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            return (isDirectory.boolValue ? "Attached folder: " : "Attached file: ") + path
        }
        return ([trimmed] + lines).filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

extension ReasoningEffort {
    static func fromLabel(_ label: String) -> ReasoningEffort {
        switch label {
        case "Low": return .low
        case "Medium": return .medium
        default: return .high
        }
    }
}
