import SwiftUI
import YuzuHarness

struct TaskThreadView: View {
    @EnvironmentObject private var model: AppModel
    let colors: ThemeColors
    let reduceMotion: Bool
    let width: CGFloat

    private var presentation: InspectorPresentation {
        model.inspectorPresentation(width: model.contentWidth)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                threadColumn
                if presentation == .beside, model.inspectorOpen {
                    inspectorPanel
                        .frame(width: 390)
                }
            }
            if presentation == .overlay, model.inspectorOpen {
                inspectorPanel
                    .frame(width: min(376, width - 20))
                    .padding(.top, 60)
                    .padding(.trailing, 10)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityID("inspector-layout-\(presentation.rawValue)")
    }

    private var threadColumn: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    model.inspectorOpen.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .buttonStyle(.plain)
                Text("Task")
                    .font(.system(size: 16, weight: .medium))
                Spacer()
            }
            .padding()
            .foregroundStyle(colors.text)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Assistant")
                        .font(.custom("Georgia", size: 16))
                        .foregroundStyle(colors.text)
                        .padding()
                        .background(colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .frame(maxWidth: CGFloat(Tokens.contentWidth), alignment: .leading)
                .padding()
            }

            VStack(spacing: 8) {
                TextField("Write a message…", text: .constant(""), axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text(AppModel.disclaimer)
                    .font(.system(size: 13))
                    .foregroundStyle(colors.dim)
                    .multilineTextAlignment(.center)
                    .accessibilityID("task-disclaimer", label: AppModel.disclaimer)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inspectorPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Task details")
                .font(.system(size: 16, weight: .medium))
                .padding()
            Text("Progress")
                .padding(.horizontal)
            Text("Progress on longer tasks appears here.")
                .font(.system(size: 14))
                .foregroundStyle(colors.dim)
                .padding(.horizontal)
                .padding(.bottom, 12)
            Divider()
            Text("Context")
                .padding()
            Text("Track tools and referenced files used in this task.")
                .font(.system(size: 14))
                .foregroundStyle(colors.dim)
                .padding(.horizontal)
            Spacer()
        }
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.line, lineWidth: 1))
        .accessibilityIdentifier("thread-inspector")
    }
}
