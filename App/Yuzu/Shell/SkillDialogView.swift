import SwiftUI
import YuzuHarness

enum SkillDialogMode: Equatable {
    case create
    case detail(name: String, description: String)
}

struct SkillDialogView: View {
    @EnvironmentObject private var model: AppModel
    let colors: ThemeColors
    let mode: SkillDialogMode
    let onClose: () -> Void

    @State private var createName = ""
    @State private var createDescription = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(alignment: .leading, spacing: 0) {
                Text(dialogTitle)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(colors.text)
                    .padding(.bottom, 12)

                switch mode {
                case .create:
                    createForm
                case .detail(_, let description):
                    Text(description.isEmpty ? "This skill has no description." : description)
                        .font(.system(size: 15))
                        .foregroundStyle(colors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button("Close", action: onClose)
                            .buttonStyle(.plain)
                            .font(.system(size: 15))
                            .foregroundStyle(colors.text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(colors.surfaceHover)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.line, lineWidth: 1))
                            .accessibilityID("skill-detail-close")
                    }
                    .padding(.top, 20)
                }
            }
            .padding(23)
            .frame(width: min(500, 500))
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(colors.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
            .accessibilityID("skill-dialog")
        }
    }

    private var dialogTitle: String {
        switch mode {
        case .create: return "Create skill"
        case .detail(let name, _): return name
        }
    }

    private var createForm: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Skill name")
                .font(.system(size: 14))
                .foregroundStyle(colors.text)
                .padding(.top, 12)
                .padding(.bottom, 5)
            TextField("", text: $createName)
                .textFieldStyle(.plain)
                .padding(10)
                .background(colors.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.line, lineWidth: 1))
                .accessibilityID("skill-create-name")

            Text("Description")
                .font(.system(size: 14))
                .foregroundStyle(colors.text)
                .padding(.top, 12)
                .padding(.bottom, 5)
            TextField("", text: $createDescription, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...6)
                .padding(10)
                .frame(minHeight: 84, alignment: .topLeading)
                .background(colors.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.line, lineWidth: 1))
                .accessibilityID("skill-create-description")

            HStack {
                Spacer()
                Button("Cancel", action: onClose)
                    .buttonStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(colors.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(colors.surfaceHover)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.line, lineWidth: 1))
                    .accessibilityID("skill-create-cancel")
                Button("Add skill") {
                    submitCreate()
                }
                .buttonStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(colors.onAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(colors.softText)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityID("skill-create-submit")
            }
            .padding(.top, 20)
        }
    }

    private func submitCreate() {
        let name = createName.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = createDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !description.isEmpty else {
            onClose()
            return
        }
        try? SkillCatalog.createProjectSkill(
            projectPath: model.workspaceProjectPath,
            name: name,
            description: description
        )
        onClose()
    }
}
