import SwiftUI

struct HandoffToast: View {
    let message: String
    let colors: ThemeColors

    var body: some View {
        Text(message)
            .font(.system(size: 14))
            .foregroundStyle(colors.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 420, alignment: .leading)
            .background(colors.surfaceHover)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
            .accessibilityID("toast", label: message)
    }
}
