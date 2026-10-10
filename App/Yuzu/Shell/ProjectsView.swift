import AppKit
import SwiftUI
import YuzuHarness

struct ProjectsView: View {
    @EnvironmentObject private var model: AppModel
    let colors: ThemeColors

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Projects")
                    .font(.custom("Georgia", size: 32))
                    .foregroundStyle(colors.text)

                if model.knownProjectFolders.isEmpty {
                    Text("No project yet")
                        .font(.system(size: 17))
                        .foregroundStyle(colors.muted)
                    Text("Choose a folder to set where the next task opens.")
                        .font(.system(size: 15))
                        .foregroundStyle(colors.dim)
                    Button("Choose folder") {
                        chooseFolder()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(colors.selected)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityID("projects-choose-folder")
                } else {
                    ForEach(model.knownProjectFolders, id: \.path) { url in
                        projectRow(url)
                    }
                }
            }
            .frame(maxWidth: 806, alignment: .leading)
            .padding(40)
        }
        .scrollIndicators(.never)
    }

    private func projectRow(_ url: URL) -> some View {
        let selected = model.nextProjectPath == url.path
            || (model.nextProjectPath == nil && model.workspaceProjectPath == url.path)
        return HStack(spacing: 12) {
            Button {
                model.setProjectFolder(url)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "folder")
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent)
                            .font(.system(size: 16, weight: .medium))
                        Text(url.deletingLastPathComponent().path)
                            .font(.system(size: 13))
                            .foregroundStyle(colors.dim)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if selected {
                        Text("Next task")
                            .font(.system(size: 13))
                            .foregroundStyle(colors.muted)
                    }
                }
                .foregroundStyle(colors.text)
                .padding(14)
                .background(colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityID("project-row-\(url.lastPathComponent)")

            Button("New task") {
                model.setProjectFolder(url)
                model.beginTask()
                model.selectCowork(.task)
            }
            .buttonStyle(.plain)
            .font(.system(size: 14))
            .foregroundStyle(colors.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(colors.surfaceHover)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityID("project-new-task-\(url.lastPathComponent)")
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.setProjectFolder(url)
        }
    }
}
