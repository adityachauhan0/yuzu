import SwiftUI
import YuzuHarness

struct CodeHomeView: View {
    @EnvironmentObject private var model: AppModel
    let colors: ThemeColors
    @State private var prompt = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer()
            composer
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Code")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(colors.text)
            HStack(spacing: 16) {
                Text("Overview")
                    .foregroundStyle(colors.accent)
                Text("Models")
                    .foregroundStyle(colors.muted)
            }
            .font(.system(size: 15))
            metricRow
        }
        .padding(.top, 28)
        .frame(maxWidth: CGFloat(Tokens.contentWidth), alignment: .leading)
    }

    private var metricRow: some View {
        HStack(spacing: 24) {
            metric("Sessions", value: "0")
            metric("Messages", value: "0")
            metric("Total tokens", value: "0")
            Spacer()
            Text("—")
                .font(.system(size: 11))
                .foregroundStyle(colors.dim)
                .accessibilityID("code-speed", label: "speed —")
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(colors.dim)
            Text(value)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(colors.text)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button {
                } label: {
                    Label("Local", systemImage: "desktopcomputer")
                        .font(.system(size: 13))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(colors.selected)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityID("code-local")

                Button("Select folder…") {}
                    .buttonStyle(.plain)
                    .foregroundStyle(colors.muted)
                    .font(.system(size: 13))
            }

            VStack(spacing: 0) {
                TextField("Describe a task or ask a question", text: $prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(16)
                    .foregroundStyle(colors.text)

                HStack {
                    Button("+") {}
                        .buttonStyle(.plain)
                        .foregroundStyle(colors.muted)
                    Button {
                        Task { await model.toggleManual() }
                    } label: {
                        Text("Manual")
                            .font(.system(size: 13))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(model.manualPressed ? colors.selected : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityID("code-manual")
                    Spacer()
                    Button("High") {}
                        .buttonStyle(.plain)
                        .foregroundStyle(colors.muted)
                    Button {
                        Task { await model.sendPrompt(prompt) }
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(colors.accent)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(colors.line, lineWidth: 1))
        }
        .frame(maxWidth: CGFloat(Tokens.contentWidth))
    }
}
