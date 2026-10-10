import Foundation
import YuzuHarness

struct ToolRowItem: Equatable {
    var call: ToolCall
    var presentation: ToolRowPresentation
    var result: String
}

/// What the thread draws: user bubbles, assistant replies, tool rows, and compaction markers.
enum ThreadItem: Equatable {
    case user(String)
    case thought(String)
    case reply(text: String)
    case tools(label: String, rows: [ToolRowItem])
    case compaction

    static func build(
        _ transcript: [StoredMessage],
        events: [HarnessEventRecord] = []
    ) -> [ThreadItem] {
        var items: [ThreadItem] = []
        var pendingCalls: [ToolCall] = []
        var settled: [(ToolCall, String)] = []
        func flushTools() {
            guard !settled.isEmpty else { return }
            let rows = settled.map { call, result in
                ToolRowItem(
                    call: call,
                    presentation: ToolRowFormatter.present(call: call, result: result),
                    result: result
                )
            }
            let label = settled.count == 1
                ? "\(rows[0].presentation.title) \(rows[0].presentation.detail)".trimmingCharacters(in: .whitespaces)
                : ToolRowFormatter.groupLabel(toolCount: settled.count)
            items.append(.tools(label: label, rows: rows))
            settled = []
        }

        for message in transcript {
            switch message.role {
            case .user:
                flushTools()
                pendingCalls = []
                items.append(.user(message.text))
            case .assistant:
                flushTools()
                pendingCalls = message.toolCalls
                let reasoning = message.reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
                if !reasoning.isEmpty {
                    items.append(.thought(reasoning))
                }
                let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    items.append(.reply(text: message.text))
                }
            case .tool:
                if let index = pendingCalls.firstIndex(where: { $0.id == message.toolCallID }) {
                    let call = pendingCalls.remove(at: index)
                    settled.append((call, message.text))
                } else if let id = message.toolCallID, let name = message.toolName {
                    settled.append((
                        ToolCall(id: id, name: name, arguments: .object([:])),
                        message.text
                    ))
                }
            case .system:
                flushTools()
                if message.text.contains("Earlier context was summarized") {
                    items.append(.compaction)
                }
            case .developer:
                break
            }
        }
        flushTools()
        if !items.contains(.compaction) {
            for event in events where event.name == "compaction.applied" {
                _ = event
                items.append(.compaction)
            }
        }
        return items
    }
}

extension JSONValue {
    /// Compact one-line JSON for debugging.
    var compactText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
