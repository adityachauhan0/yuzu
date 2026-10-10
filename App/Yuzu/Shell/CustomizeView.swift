import SwiftUI

struct CustomizeView: View {
    let colors: ThemeColors

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Customize")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(colors.text)
            HStack {
                Text("Skills")
                    .foregroundStyle(colors.accent)
                Text("Connectors")
                    .foregroundStyle(colors.muted)
                Text("Plugins")
                    .foregroundStyle(colors.muted)
            }
            .font(.system(size: 15))

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add your first skills")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(colors.text)
                    Text("Skills teach Yuzu how you work.")
                        .font(.system(size: 14))
                        .foregroundStyle(colors.muted)
                        .accessibilityID("skills-banner", label: "Skills teach Yuzu how you work.")
                }
                Spacer()
            }
            .padding(16)
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
