import SwiftUI
import YuzuHarness

struct ThreadToolGroupView: View {
    let colors: ThemeColors
    let label: String
    let rows: [ToolRowItem]
    var onOpenTask: ((ToolCall) -> Void)?

    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if rows.count == 1, let row = rows.first {
            ThreadToolRowView(colors: colors, row: row, onOpenTask: onOpenTask)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    expanded.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Text(label)
                            .font(.system(size: 16))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                            .rotationEffect(.degrees(expanded ? 0 : -90))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(colors.dim)
                }
                .buttonStyle(.plain)
                .accessibilityID("thread-tool-group")

                if expanded {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        ThreadToolRowView(
                            colors: colors,
                            row: row,
                            onOpenTask: onOpenTask
                        )
                    }
                }
            }
            .animation(MotionTiming.animation(reduceMotion: reduceMotion), value: expanded)
        }
    }
}

struct ThreadToolRowView: View {
    let colors: ThemeColors
    let row: ToolRowItem
    var onOpenTask: ((ToolCall) -> Void)?

    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if row.call.name == "task", onOpenTask != nil {
            Button {
                onOpenTask?(row.call)
            } label: {
                rowHeader
            }
            .buttonStyle(.plain)
            .accessibilityID("thread-task-row")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    expanded.toggle()
                } label: {
                    rowHeader
                }
                .buttonStyle(.plain)
                .accessibilityID("thread-tool-\(row.presentation.title.lowercased())")
                if expanded {
                    Text(row.result)
                        .font(YuzuFonts.code("Menlo", size: 13))
                        .foregroundStyle(colors.muted)
                        .textSelection(.enabled)
                        .padding(.leading, 4)
                        .accessibilityID("thread-tool-result")
                }
            }
            .animation(MotionTiming.animation(reduceMotion: reduceMotion), value: expanded)
        }
    }

    private var rowHeader: some View {
        HStack(spacing: 8) {
            Text(row.presentation.title)
                .font(.system(size: 15, weight: .medium))
            Text(row.presentation.detail)
                .font(.system(size: 15))
                .lineLimit(1)
            Spacer(minLength: 0)
            if row.call.name != "task" {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
                    .rotationEffect(.degrees(expanded ? 0 : -90))
            }
        }
        .foregroundStyle(colors.dim)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityID(
            "thread-tool-row",
            label: "\(row.presentation.title) \(row.presentation.detail)"
        )
    }
}

struct ThinkingLine: View {
    let colors: ThemeColors
    let reduceMotion: Bool
    @State private var dimmed = false

    var body: some View {
        Text("Thinking...")
            .font(.system(size: 16))
            .foregroundStyle(colors.dim)
            .opacity(reduceMotion || !dimmed ? 1 : 0.4)
            .padding(.top, 20)
            .accessibilityID("thread-thinking")
            .accessibilityID("thread-status-thinking", label: "Thinking")
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
    }
}

struct ThreadThoughtRow: View {
    let colors: ThemeColors
    let text: String
    var streaming = false
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text(streaming ? "Thinking..." : "Thought")
                        .font(.system(size: 16, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                        .rotationEffect(.degrees((streaming || expanded) ? 0 : -90))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(colors.dim)
            }
            .buttonStyle(.plain)
            .accessibilityID("thread-thought")
            if streaming || expanded {
                Text(text)
                    .font(.system(size: 15))
                    .foregroundStyle(colors.muted)
                    .textSelection(.enabled)
            }
        }
    }
}
