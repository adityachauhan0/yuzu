import SwiftUI
import YuzuHarness

private enum CustomizeTab: String, CaseIterable {
    case skills = "Skills"
    case connectors = "Connectors"
    case plugins = "Plugins"
}

struct CustomizeView: View {
    @EnvironmentObject private var model: AppModel
    let colors: ThemeColors
    @State private var tab: CustomizeTab = .skills

    private var skills: [SkillRecord] {
        SkillCatalog.discover(projectPath: model.workspaceProjectPath)
    }

    private var yuzuSkills: [SkillRecord] {
        skills.filter { $0.directoryPath.contains("EmbeddedSkills") }
    }

    private var userSkills: [SkillRecord] {
        skills.filter { !$0.directoryPath.contains("EmbeddedSkills") }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Customize")
                    .font(.custom("Georgia", size: 32))
                    .foregroundStyle(colors.text)
                    .tracking(-1.28)

                HStack(spacing: 2) {
                    ForEach(CustomizeTab.allCases, id: \.self) { item in
                        customizeTabButton(item)
                    }
                    Spacer()
                }
                .padding(.top, 26)

                switch tab {
                case .skills:
                    skillsPanel
                case .connectors:
                    otherPanel(title: "Connectors", copy: "No servers added.")
                case .plugins:
                    otherPanel(title: "Plugins", copy: "No plugins yet.")
                }
            }
            .frame(maxWidth: 1152, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 65)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func customizeTabButton(_ item: CustomizeTab) -> some View {
        Button {
            tab = item
        } label: {
            Text(item.rawValue)
                .font(.system(size: 16))
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .background(tab == item ? colors.selected : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .foregroundStyle(tab == item ? colors.text : colors.dim)
        .accessibilityIdentifier("customize-tab-\(item.rawValue)")
    }

    private var skillsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add your first skills")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(colors.text)
                    Text("Skills teach Yuzu how you work.")
                        .font(.system(size: 16))
                        .foregroundStyle(colors.muted)
                        .accessibilityID("skills-banner", label: "Skills teach Yuzu how you work.")
                }
                Spacer()
                PaperPlaneDecoration()
                    .stroke(colors.text, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .frame(width: 82, height: 70)
                    .padding(.trailing, 6)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 19)
            .padding(.vertical, 22)
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.top, 32)

            if !yuzuSkills.isEmpty {
                skillHeading(title: "From Yuzu", count: yuzuSkills.count)
                ForEach(yuzuSkills, id: \.name) { skill in
                    skillRow(skill, source: "from Yuzu")
                }
            }

            if !userSkills.isEmpty {
                skillHeading(title: "From you", count: userSkills.count)
                ForEach(userSkills, id: \.name) { skill in
                    skillRow(skill, source: "from you")
                }
            }
        }
    }

    private func otherPanel(title: String, copy: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(colors.text)
            Text(copy)
                .font(.system(size: 16))
                .foregroundStyle(colors.muted)
        }
        .padding(.top, 33)
        .padding(.vertical, 24)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(colors.line)
                .frame(height: 1)
        }
    }

    private func skillHeading(title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(colors.text)
            Text("· \(count)")
                .font(.system(size: 13))
                .foregroundStyle(colors.dim)
        }
        .padding(.top, 38)
        .padding(.bottom, 10)
        .accessibilityIdentifier("skill-heading-\(title)")
    }

    private func skillRow(_ skill: SkillRecord, source: String) -> some View {
        Button {} label: {
            HStack(alignment: .center, spacing: 20) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 18))
                    .foregroundStyle(colors.dim)
                    .frame(width: 43, height: 43)
                    .background(colors.side)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.line, lineWidth: 1))

                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.name)
                        .font(.system(size: 16))
                        .foregroundStyle(colors.text)
                        .lineLimit(1)
                    HStack(spacing: 0) {
                        Text(source)
                            .foregroundStyle(colors.muted)
                        Text(" · ")
                            .foregroundStyle(colors.dim)
                        Text(skill.description)
                            .foregroundStyle(colors.dim)
                            .lineLimit(1)
                    }
                    .font(.system(size: 15))
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 9)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(colors.line)
                    .frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("skill-row-\(skill.name)")
    }
}

private struct PaperPlaneDecoration: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 82
        let sy = rect.height / 70
        var path = Path()
        path.move(to: CGPoint(x: 7 * sx, y: 24 * sy))
        path.addLine(to: CGPoint(x: 73 * sx, y: 5 * sy))
        path.addLine(to: CGPoint(x: 53 * sx, y: 66 * sy))
        path.addLine(to: CGPoint(x: 36 * sx, y: 46 * sy))
        path.closeSubpath()
        path.move(to: CGPoint(x: 36 * sx, y: 46 * sy))
        path.addLine(to: CGPoint(x: 73 * sx, y: 5 * sy))
        path.addLine(to: CGPoint(x: 24 * sx, y: 34 * sy))
        path.move(to: CGPoint(x: 36 * sx, y: 46 * sy))
        path.addLine(to: CGPoint(x: 53 * sx, y: 66 * sy))
        path.addLine(to: CGPoint(x: 42 * sx, y: 41 * sy))
        path.addLine(to: CGPoint(x: 73 * sx, y: 5 * sy))
        return path
    }
}
