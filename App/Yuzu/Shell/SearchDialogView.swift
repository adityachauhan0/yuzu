import SwiftUI

/// `.search-dialog`: **Search this workspace** over pages, tasks, skills and Settings tabs.
struct SearchDialogView: View {
    @EnvironmentObject private var model: AppModel
    let colors: ThemeColors
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        let results = model.searchResults(query)
        ZStack(alignment: .top) {
            (model.isDarkAppearance ? Color.black.opacity(0.6) : Color(hex: "#23382B").opacity(0.4))
                .ignoresSafeArea()
                .onTapGesture { model.searchOpen = false }
            VStack(alignment: .leading, spacing: 0) {
                Text("Search this workspace")
                    .font(.system(size: 13))
                    .foregroundStyle(colors.muted)
                    .padding(.bottom, 8)
                TextField("Search tasks and sections", text: $query)
                    .textFieldStyle(.plain).yuzuFieldHover()
                    .font(.system(size: 15))
                    .foregroundStyle(colors.text)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(model.isDarkAppearance ? Color(hex: "#202326") : Color(hex: "#EEF2EE"))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(border, lineWidth: 1))
                    .focused($focused)
                    .onSubmit { results.first.map(open) }
                    .accessibilityID("search-input", label: "Search this workspace")
                VStack(alignment: .leading, spacing: 0) {
                    if results.isEmpty {
                        Text("No matching items.")
                            .font(.system(size: 14))
                            .foregroundStyle(colors.muted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .accessibilityID("search-empty")
                    } else {
                        ForEach(results) { result in
                            SearchResultRow(label: result.label, colors: colors) { open(result) }
                                .accessibilityID("search-result", label: result.label)
                        }
                    }
                }
                .padding(.top, 8)
            }
            .padding(14)
            .frame(width: 560)
            .background(colors.preview)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(border, lineWidth: 1))
            .shadow(color: .black.opacity(model.isDarkAppearance ? 0.6 : 0.15), radius: 30, y: 20)
            .padding(.top, 170)
            .accessibilityID("search-dialog")
        }
        .onAppear { focused = true }
    }

    private var border: Color {
        model.isDarkAppearance ? Color(hex: "#465054") : Color(hex: "#B0C0B4")
    }

    private func open(_ result: AppModel.SearchResult) {
        model.searchOpen = false
        result.open()
    }
}

private struct SearchResultRow: View {
    let label: String
    let colors: ThemeColors
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(colors.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 39, alignment: .leading)
                .padding(.horizontal, 10)
                .background(hovering ? colors.line : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.yuzu)
        .onHover { hovering = $0 }
    }
}
