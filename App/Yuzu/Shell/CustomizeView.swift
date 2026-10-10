import SwiftUI
import YuzuHarness

enum CustomizeTab: String, CaseIterable {
    case skills = "Skills"
    case connectors = "Connectors"
}

private enum SkillSourceFilter: String, CaseIterable {
    case all = "All sources"
    case yuzu = "From Yuzu"
    case you = "From you"
}

struct CustomizeView: View {
    @EnvironmentObject private var model: AppModel
    let colors: ThemeColors
    @State private var tab: CustomizeTab = .skills
    /// Settings shows one pane inside its own main column, without the page title or tabs.
    var embeddedTab: CustomizeTab?
    @State private var searchVisible = false
    @State private var searchQuery = ""
    @State private var filterMenuOpen = false
    @State private var addMenuOpen = false
    @State private var sourceFilter: SkillSourceFilter = .all
    @State private var skillsReversed = false
    @State private var skillDialog: SkillDialogMode?
    @State private var skillsRefresh = 0
    @State private var mcpName = ""
    @State private var mcpCommand = ""
    @State private var mcpArgs = ""

    private var skills: [SkillRecord] {
        _ = skillsRefresh
        return SkillCatalog.discover(projectPath: model.workspaceProjectPath)
    }

    private var yuzuSkills: [SkillRecord] {
        filtered(skills.filter { $0.directoryPath.contains("EmbeddedSkills") })
    }

    private var userSkills: [SkillRecord] {
        filtered(skills.filter { !$0.directoryPath.contains("EmbeddedSkills") })
    }

    var body: some View {
        ZStack {
            if let embeddedTab {
                VStack(alignment: .leading, spacing: 0) {
                    if embeddedTab == .skills {
                        HStack {
                            Spacer()
                            skillsActions
                        }
                    }
                    panel(embeddedTab)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Customize")
                            .font(.custom("Georgia", size: 32))
                            .foregroundStyle(colors.text)
                            .tracking(-1.28)

                        customizeToolbar
                            .padding(.top, 26)

                        panel(tab)
                    }
                    .frame(maxWidth: 1152, alignment: .leading)
                    .padding(.horizontal, 40)
                    .padding(.top, 65)
                    .padding(.bottom, 36)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.never)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            if let dialog = skillDialog {
                SkillDialogView(colors: colors, mode: dialog) {
                    skillDialog = nil
                    skillsRefresh += 1
                }
            }
        }
        .onChange(of: model.requestedSkill, initial: true) { _, name in
            guard let name else { return }
            model.requestedSkill = nil
            tab = .skills
            if let skill = skills.first(where: { $0.name == name }) {
                skillDialog = .detail(name: skill.name, description: skill.description)
            }
        }
        .dismissesOnEscape($filterMenuOpen)
        .dismissesOnEscape($addMenuOpen)
        .dismissesOnEscape(when: searchVisible) {
            searchVisible = false
            searchQuery = ""
        }
        .dismissesOnEscape(when: skillDialog != nil) { skillDialog = nil }
    }

    @ViewBuilder
    private func panel(_ tab: CustomizeTab) -> some View {
        switch tab {
        case .skills:
            skillsPanel
        case .connectors:
            connectorsPanel
        }
    }

    private var customizeToolbar: some View {
        HStack(alignment: .center, spacing: 24) {
            HStack(spacing: 2) {
                ForEach(CustomizeTab.allCases, id: \.self) { item in
                    customizeTabButton(item)
                }
            }

            Spacer()

            if tab == .skills {
                skillsActions
            }
        }
    }

    private var skillsActions: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 9) {
                Button {
                    searchVisible.toggle()
                    if !searchVisible { searchQuery = "" }
                    filterMenuOpen = false
                    addMenuOpen = false
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .frame(width: 35, height: 37)
                }
                .buttonStyle(.plain)
                .foregroundStyle(colors.muted)
                .background(searchVisible ? colors.selected : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityID("customize-search-button")

                Button {
                    filterMenuOpen.toggle()
                    addMenuOpen = false
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16))
                        .frame(width: 35, height: 37)
                }
                .buttonStyle(.plain)
                .foregroundStyle(colors.muted)
                .background(filterMenuOpen ? colors.selected : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityID("customize-filter-button")

                Button {
                    skillsReversed.toggle()
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 16))
                        .frame(width: 35, height: 37)
                }
                .buttonStyle(.plain)
                .foregroundStyle(colors.muted)
                .accessibilityID("customize-sort-button")

                Button {
                    addMenuOpen.toggle()
                    filterMenuOpen = false
                } label: {
                    HStack(spacing: 7) {
                        Text("Add")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                    }
                    .font(.system(size: 16))
                    .foregroundStyle(colors.onAccent)
                    .padding(.horizontal, 12)
                    .frame(minWidth: 85, minHeight: 38)
                    .background(colors.softText)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityID("customize-add-button")
            }

            if searchVisible {
                TextField("Search skills", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(width: 340)
                    .background(colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(colors.line, lineWidth: 1))
                    .padding(.top, 45)
                    .accessibilityID("customize-search-field")
            }

            if filterMenuOpen {
                HandoffPopover(colors: colors) {
                    HandoffMenuLabel(title: "Source", colors: colors)
                    ForEach(SkillSourceFilter.allCases, id: \.self) { filter in
                        HandoffPopoverRow(title: filter.rawValue, colors: colors) {
                            sourceFilter = filter
                            filterMenuOpen = false
                        }
                        .accessibilityIdentifier("customize-filter-\(filter.rawValue)")
                    }
                }
                .padding(.top, 45)
                .padding(.trailing, 100)
            }

            if addMenuOpen {
                HandoffPopover(colors: colors) {
                    HandoffPopoverRow(title: "Create skill", colors: colors) {
                        addMenuOpen = false
                        skillDialog = .create
                    }
                    .accessibilityID("create-skill-option")
                }
                .padding(.top, 45)
            }
        }
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

            if !yuzuSkills.isEmpty, sourceFilter != .you {
                skillHeading(title: "From Yuzu", count: yuzuSkills.count)
                ForEach(yuzuSkills, id: \.name) { skill in
                    skillRow(skill, source: "from Yuzu")
                }
            }

            if !userSkills.isEmpty, sourceFilter != .yuzu {
                skillHeading(title: "From you", count: userSkills.count)
                ForEach(userSkills, id: \.name) { skill in
                    skillRow(skill, source: "from you")
                }
            }
        }
    }

    private func filtered(_ list: [SkillRecord]) -> [SkillRecord] {
        var result = list
        let term = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !term.isEmpty {
            result = result.filter {
                $0.name.lowercased().contains(term) || $0.description.lowercased().contains(term)
            }
        }
        if skillsReversed {
            result.reverse()
        }
        return result
    }

    private var connectorsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connectors")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(colors.text)
            if model.mcpServerLines.isEmpty {
                Text("No servers added.")
                    .font(.system(size: 16))
                    .foregroundStyle(colors.muted)
            } else {
                ForEach(model.mcpServerLines, id: \.self) { line in
                    connectorRow(line)
                }
            }
            TextField("Server name", text: $mcpName)
                .textFieldStyle(.plain)
                .padding(8)
                .background(colors.surface)
                .foregroundStyle(colors.text)
                .accessibilityID("mcp-add-name")
            TextField("Command, or leave empty for DuckDuckGo", text: $mcpCommand)
                .textFieldStyle(.plain)
                .padding(8)
                .background(colors.surface)
                .foregroundStyle(colors.text)
            TextField("Args, separated by spaces", text: $mcpArgs)
                .textFieldStyle(.plain)
                .padding(8)
                .background(colors.surface)
                .foregroundStyle(colors.text)
            HStack(spacing: 10) {
                Button("Add") {
                    let args = mcpArgs.split(whereSeparator: \.isWhitespace).map(String.init)
                    model.installMCPServer(name: mcpName, command: mcpCommand, args: args)
                    mcpName = ""
                    mcpCommand = ""
                    mcpArgs = ""
                }
                .buttonStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(colors.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(colors.surfaceHover)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityID("connectors-add")
                Button("Edit JSON") {
                    model.openSettings(tab: .developer, anchor: .mcpConfig)
                }
                .buttonStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(colors.muted)
            }
        }
        .padding(.top, 33)
    }

    /// `.skill-row`: the server name, and its status in the meta line.
    private func connectorRow(_ line: String) -> some View {
        let name = mcpServerName(line) ?? line
        let status = line.split(separator: "·", maxSplits: 1).dropFirst().first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return HStack(alignment: .center, spacing: 20) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 18))
                .foregroundStyle(colors.dim)
                .frame(width: 43, height: 43)
                .background(colors.side)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.line, lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 16))
                    .foregroundStyle(colors.text)
                Text(status)
                    .font(.system(size: 14))
                    .foregroundStyle(colors.dim)
            }
            Spacer(minLength: 0)
            if status == "connected" {
                Button("Disconnect") {
                    model.disconnectMCPServer(named: name)
                }
                .buttonStyle(.plain)
                .foregroundStyle(colors.muted)
            } else if status == "needs auth" {
                Button("Sign in") { model.beginMCPSignIn(serverName: name) }
                    .buttonStyle(.plain)
                    .foregroundStyle(colors.text)
                    .accessibilityID("mcp-sign-in-\(name)")
            } else if status != "disabled" {
                Button("Connect") {
                    Task { await model.connectMCPServer(named: name) }
                }
                .buttonStyle(.plain)
                .foregroundStyle(colors.text)
            }
            Button("Remove") {
                model.removeMCPServer(named: name)
            }
            .buttonStyle(.plain)
            .foregroundStyle(colors.dim)
        }
        .padding(.vertical, 8)
        .accessibilityID("connector-row", label: "\(name), \(status)")
    }

    private func mcpServerName(_ line: String) -> String? {
        let name = line.split(separator: "·").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return name.isEmpty ? nil : name
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
        Button {
            skillDialog = .detail(name: skill.name, description: skill.description)
        } label: {
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
