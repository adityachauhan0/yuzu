import SwiftUI
import YuzuHarness

struct CoworkHomeView: View {
    @EnvironmentObject private var model: AppModel
    let colors: ThemeColors
    @State private var prompt = ""

    private var isDark: Bool { model.theme == .dark }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            welcomeHeading
            composer
            ideas
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var welcomeHeading: some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if let logo = HandoffImage.coworkLogo(dark: isDark) {
                    logo
                        .resizable()
                        .scaledToFit()
                        .frame(width: 42, height: 42)
                } else {
                    Image(systemName: "sparkle")
                        .font(.system(size: 32))
                }
            }
            .accessibilityHidden(true)

            Text(AccountName.coworkWelcomeLine)
                .font(.custom("Georgia", size: 44))
                .foregroundStyle(colors.text)
                .tracking(-2.2)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(minHeight: 62)
        .padding(.bottom, 16)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            TextField("How can I help you today?", text: $prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...4)
                .padding(16)
                .background(colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(colors.line, lineWidth: 1))
            HStack {
                Spacer()
                Button {
                    Task { await model.sendPrompt(prompt) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                }
                .buttonStyle(.plain)
                .foregroundStyle(colors.accent)
            }
        }
        .frame(maxWidth: CGFloat(Tokens.contentWidth))
    }

    private var ideas: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ideas for you")
                .font(.system(size: 14))
                .foregroundStyle(colors.dim)
            HStack {
                ideaButton("Send me a daily briefing")
                ideaButton("Organize my inbox")
                ideaButton("Customize Cowork for me")
            }
        }
        .frame(maxWidth: CGFloat(Tokens.contentWidth), alignment: .leading)
    }

    private func ideaButton(_ title: String) -> some View {
        Button {
            prompt = title
        } label: {
            Text(title)
                .font(.system(size: 14))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .foregroundStyle(colors.muted)
    }
}
