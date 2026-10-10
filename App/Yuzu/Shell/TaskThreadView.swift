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

    private var presentation: InspectorPresentation {
        model.inspectorPresentation(width: model.contentWidth)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                threadColumn
                if presentation == .beside, model.inspectorOpen {
                    inspectorPanel
                        .frame(width: 390)
                }
            }
            if presentation == .overlay, model.inspectorOpen {
                inspectorPanel
                    .frame(width: min(376, width - 20))
                    .padding(.top, 60)
                    .padding(.trailing, 10)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityID("inspector-layout-\(presentation.rawValue)")
    }

    private var threadColumn: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    model.inspectorOpen.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .buttonStyle(.plain)
                Menu {
                    Button("Rename") {
                        renameDraft = model.taskTitle
                        renameOpen = true
                    }
                    Button("Pin") { model.taskPinned.toggle() }
                    Button("Normal") { model.transcriptView = "Normal" }
                    Button("Thinking") { model.transcriptView = "Thinking" }
                    Button("Verbose") { model.transcriptView = "Verbose" }
                    Button("Delete") { model.deleteCurrentTask() }
                } label: {
                    Text(model.taskTitle)
                        .font(.system(size: 16, weight: .medium))
                }
                .accessibilityID("thread-title")
                Spacer()
            }
            .padding()
            .foregroundStyle(colors.text)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(model.transcript.enumerated()), id: \.offset) { _, message in
                        threadBubble(message)
                    }
                }
                .frame(maxWidth: model.transcriptColumnMax, alignment: .leading)
                .padding()
            }
            .onAppear { model.reloadTranscript() }
            .overlay {
                if renameOpen {
                    renameDialog
                }
            }

            VStack(spacing: 8) {
                TextField("Write a message…", text: $model.threadDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(YuzuFonts.interface(model.interfaceFont, size: 16))
                    .padding(12)
                    .background(colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onSubmit { Task { await model.submitThread() } }
                if model.turnRunning {
                    Button("Stop") {
                        Task { await model.stopTurn() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(colors.text)
                    .accessibilityID("stop-turn")
                }
                Text(AppModel.disclaimer)
                    .font(.system(size: 13))
                    .foregroundStyle(colors.dim)
                    .multilineTextAlignment(.center)
                    .accessibilityID("task-disclaimer", label: AppModel.disclaimer)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func threadBubble(_ message: StoredMessage) -> some View {
        switch message.role {
        case .user:
            Text(message.text)
                .font(YuzuFonts.interface(model.interfaceFont, size: 16))
                .foregroundStyle(colors.text)
                .padding()
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                if model.transcriptView != "Normal", !message.reasoning.isEmpty {
                    Text(message.reasoning)
                        .font(.system(size: 13))
                        .foregroundStyle(colors.dim)
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(model.chatFont == "System" ? .system(size: model.transcriptFontSize) : .custom("Georgia", size: model.transcriptFontSize))
                        .foregroundStyle(colors.text)
                }
                if model.transcriptView == "Verbose", !message.toolCalls.isEmpty {
                    Text(message.toolCalls.map { "\($0.name) \($0.arguments)" }.joined(separator: "\n"))
                        .font(.system(size: 13))
                        .foregroundStyle(colors.muted)
                }
            }
            .padding()
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        case .tool:
            Text(message.toolName == "bash"
                 ? "Updated tasks, ran \(model.commandCount) command\(model.commandCount == 1 ? "" : "s")."
                 : (message.toolName.map { "Ran \($0)" } ?? "Ran a tool"))
                .font(.system(size: 13))
                .foregroundStyle(colors.muted)
        case .system, .developer:
            EmptyView()
        }
    }

    private var inspectorPanel: some View {
        let folder = URL(fileURLWithPath: model.workspaceProjectPath).lastPathComponent
        return VStack(alignment: .leading, spacing: 0) {
            Text("Task details")
                .font(.system(size: 16, weight: .medium))
                .padding()
            Text("Progress")
                .padding(.horizontal)
            Text("Progress on longer tasks appears here.")
                .font(.system(size: 14))
                .foregroundStyle(colors.dim)
                .padding(.horizontal)
                .padding(.bottom, 12)
            Divider()
            HStack {
                Text(folder.isEmpty ? "Project" : folder)
                Spacer()
                Button("Open") {
                    let path = model.workspaceProjectPath
                    guard !path.isEmpty else { return }
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                }
                .buttonStyle(.plain)
                .accessibilityID("inspector-open-folder")
            }
            .padding(.horizontal)
            .padding(.top, 12)
            if model.createdArtifactPaths.isEmpty {
                Text("View and open files created during this task.")
                    .font(.system(size: 14))
                    .foregroundStyle(colors.dim)
                    .padding(.horizontal)
                    .padding(.bottom, 12)
            } else {
                ForEach(model.createdArtifactPaths, id: \.self) { path in
                    Button(URL(fileURLWithPath: path).lastPathComponent) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(colors.text)
                    .padding(.horizontal)
                }
                .padding(.bottom, 12)
            }
            Divider()
            Text("Context")
                .padding(.horizontal)
                .padding(.top, 12)
            if model.referencedToolNames.isEmpty {
                Text("Track tools and referenced files used in this task.")
                    .font(.system(size: 14))
                    .foregroundStyle(colors.dim)
                    .padding(.horizontal)
            } else {
                ForEach(model.referencedToolNames, id: \.self) { name in
                    Text(name)
                        .font(.system(size: 14))
                        .foregroundStyle(colors.muted)
                        .padding(.horizontal)
                }
            }
            Spacer()
        }
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.line, lineWidth: 1))
        .accessibilityIdentifier("thread-inspector")
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
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(colors.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.line, lineWidth: 1))
                HStack {
                    Spacer()
                    Button("Cancel") { renameOpen = false }
                        .buttonStyle(.plain)
                    Button("Save") {
                        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { model.taskTitle = trimmed }
                        renameOpen = false
                    }
                    .buttonStyle(.plain)
                    .accessibilityID("thread-rename-save")
                }
            }
            .padding(22)
            .frame(width: 420)
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}
