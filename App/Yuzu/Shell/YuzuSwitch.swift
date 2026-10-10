import SwiftUI

/// Custom switch using theme toggle colors (not `Toggle` `.switch`).
struct YuzuSwitch: View {
    let colors: ThemeColors
    @Binding var isOn: Bool
    var accessibilityID: String?

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            RoundedRectangle(cornerRadius: 10)
                .fill(isOn ? colors.toggleOn : colors.line)
                .frame(width: 36, height: 20)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(isOn ? colors.toggleOnText : colors.text)
                        .frame(width: 16, height: 16)
                        .padding(2)
                }
        }
        .buttonStyle(.yuzu)
        .accessibilityID(accessibilityID ?? "yuzu-switch", label: isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}
