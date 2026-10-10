import SwiftUI

struct HandoffPopover<Content: View>: View {
    let colors: ThemeColors
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            content()
        }
        .padding(6)
        .frame(minWidth: 200)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }
}

struct HandoffMenuLabel: View {
    let title: String
    let colors: ThemeColors

    var body: some View {
        Text(title)
            .font(.system(size: 12))
            .foregroundStyle(colors.dim)
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }
}

struct HandoffPopoverRow: View {
    let title: String
    let colors: ThemeColors
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(colors.text)
    }
}
