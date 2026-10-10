import Foundation
import YuzuHarness

/// What the thread draws: user bubbles, assistant replies, and one activity line per tool settlement.
enum ThreadItem: Equatable {
    case user(String)
    case reply(text: String, reasoning: String)
    case activity(summary: String, calls: [ToolCall])

    static func build(_ transcript: [StoredMessage]) -> [ThreadItem] {
        var items: [ThreadItem] = []
        var pendingCalls: [ToolCall] = []
        var settled: [ToolCall] = []

        func flush() {
            guard !settled.isEmpty else { return }
            items.append(.activity(summary: activitySummary(settled), calls: settled))
            settled = []
        }

        for message in transcript {
            switch message.role {
            case .user:
                flush()
                pendingCalls = []
                items.append(.user(message.text))
            case .assistant:
                flush()
                let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty || !message.reasoning.isEmpty {
                    items.append(.reply(text: message.text, reasoning: message.reasoning))
                }
                pendingCalls = message.toolCalls
            case .tool:
                if let index = pendingCalls.firstIndex(where: { $0.id == message.toolCallID }) {
                    settled.append(pendingCalls.remove(at: index))
                } else {
                    settled.append(ToolCall(id: message.toolCallID ?? "", name: message.toolName ?? "tool", arguments: .object([:])))
                }
            case .system, .developer:
                break
            }
        }
        flush()
        return items
    }

    /// "Updated tasks, ran 2 commands", from what that settlement actually ran.
    static func activitySummary(_ calls: [ToolCall]) -> String {
        var parts: [String] = []
        if calls.contains(where: { $0.name == TodoTool.definition.name }) {
            parts.append("updated tasks")
        }
        let commands = calls.filter { $0.name == "bash" }.count
        if commands > 0 {
            parts.append("ran \(commands) command\(commands == 1 ? "" : "s")")
        }
        var others: [String] = []
        for call in calls where call.name != "bash" && call.name != TodoTool.definition.name {
            if !others.contains(call.name) { others.append(call.name) }
        }
        if !others.isEmpty {
            parts.append("used " + others.joined(separator: ", "))
        }
        let line = parts.joined(separator: ", ")
        return line.prefix(1).uppercased() + line.dropFirst()
    }
}

extension JSONValue {
    /// Compact one-line JSON for the Verbose activity line.
    var compactText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
