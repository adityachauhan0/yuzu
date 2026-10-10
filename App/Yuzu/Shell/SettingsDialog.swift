import SwiftUI

struct SettingsDialog: View {
    @EnvironmentObject private var model: AppModel
    let colors: ThemeColors

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { model.settingsPresented = false }

            HStack(spacing: 0) {
                settingsSidebar
                settingsMain
            }
            .frame(width: 820, height: 560)
            .background(colors.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(colors.line, lineWidth: 1))
            .accessibilityID("settings-dialog")
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.system(size: 13))
                .foregroundStyle(colors.dim)
                .padding(.horizontal, 12)
                .padding(.top, 12)
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button {
                    model.settingsTab = tab
                } label: {
                    Text(tab.rawValue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(model.settingsTab == tab ? colors.selected : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .foregroundStyle(colors.text)
                .accessibilityIdentifier("settings-tab-\(tab.rawValue)")
            }
            Spacer()
        }
        .frame(width: 200)
        .background(colors.side)
    }

    @ViewBuilder
    private var settingsMain: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch model.settingsTab {
                case .code:
                    Text("Code appearance")
                        .font(.system(size: 20, weight: .semibold))
                        .accessibilityID("settings-code-appearance-heading")
                        .accessibilityLabel("Code appearance")
                    Text("Light theme")
                        .foregroundStyle(colors.muted)
                    Text("Dark theme")
                        .foregroundStyle(colors.muted)
                    Text("Code font")
                        .foregroundStyle(colors.muted)
                case .general:
                    Text("General")
                        .font(.system(size: 20, weight: .semibold))
                        .accessibilityID("settings-general-heading")
                    themePicker
                case .developer:
                    Text("Developer")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Local MCP servers")
                        .foregroundStyle(colors.muted)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var themePicker: some View {
        HStack {
            ForEach(AppTheme.allCases, id: \.self) { theme in
                Button {
                    model.theme = theme
                } label: {
                    Text(theme.rawValue.capitalized)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(model.theme == theme ? colors.selected : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(colors.text)
    }
}
