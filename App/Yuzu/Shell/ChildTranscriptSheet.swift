import SwiftUI
import YuzuHarness

struct ChildTranscriptSheet: View {
    @EnvironmentObject private var model: AppModel
    let sessionID: String
    let colors: ThemeColors
    @Environment(\.dismiss) private var dismiss

    private var messages: [StoredMessage] {
        (try? model.store.messages(sessionID: sessionID)) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Subagent transcript")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(colors.text)
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.plain)
            }
            .padding(16)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                        Text(message.text)
                            .font(.system(size: 15))
                            .foregroundStyle(message.role == .user ? colors.softText : colors.text)
                            .textSelection(.enabled)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 520, height: 420)
        .background(colors.canvas)
    }
}
