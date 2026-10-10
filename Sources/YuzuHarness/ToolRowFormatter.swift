import Foundation

public struct ToolRowPresentation: Sendable, Equatable {
    public var title: String
    public var detail: String

    public init(title: String, detail: String) {
        self.title = title
        self.detail = detail
    }
}

/// Maps settled tool calls to the title and detail the thread shows.
public enum ToolRowFormatter {
    public static func groupLabel(toolCount: Int) -> String {
        "Used \(toolCount) tool\(toolCount == 1 ? "" : "s")"
    }

    public static func present(call: ToolCall, result: String? = nil) -> ToolRowPresentation {
        switch call.name {
        case "read":
            let path = stringField(call.arguments, key: "path") ?? ""
            let name = (path as NSString).lastPathComponent
            return ToolRowPresentation(title: "Read", detail: name.isEmpty ? path : name)
        case "write":
            let path = stringField(call.arguments, key: "path") ?? ""
            let name = (path as NSString).lastPathComponent
            return ToolRowPresentation(title: "Write", detail: name.isEmpty ? path : name)
        case "edit":
            let path = stringField(call.arguments, key: "path") ?? ""
            let name = (path as NSString).lastPathComponent
            return ToolRowPresentation(title: "Edit", detail: name.isEmpty ? path : name)
        case "bash":
            return ToolRowPresentation(title: "Shell", detail: stringField(call.arguments, key: "command") ?? "")
        case "grep":
            return ToolRowPresentation(title: "Grep", detail: stringField(call.arguments, key: "pattern") ?? "")
        case "glob":
            return ToolRowPresentation(title: "Glob", detail: stringField(call.arguments, key: "pattern") ?? "")
        case "skill":
            let name = stringField(call.arguments, key: "name") ?? ""
            return ToolRowPresentation(title: "Skill", detail: "Loaded \(name)")
        case "task":
            let prompt = stringField(call.arguments, key: "prompt") ?? ""
            let first = prompt.split(whereSeparator: \.isNewline).first.map(String.init) ?? prompt
            return ToolRowPresentation(title: "Task", detail: first)
        case TodoTool.definition.name:
            let summary = result?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return ToolRowPresentation(title: "Todos", detail: summary.isEmpty ? "Updated tasks" : summary)
        case QuestionTool.definition.name:
            return ToolRowPresentation(title: "Question", detail: stringField(call.arguments, key: "question") ?? "")
        case "webfetch":
            let url = stringField(call.arguments, key: "url") ?? ""
            return ToolRowPresentation(title: "Web fetch", detail: url)
        case "mcp":
            let name = stringField(call.arguments, key: "name") ?? ""
            let action = stringField(call.arguments, key: "action") ?? "list"
            return ToolRowPresentation(title: "MCP", detail: "\(action) \(name)".trimmingCharacters(in: .whitespaces))
        default:
            return ToolRowPresentation(title: call.name, detail: "")
        }
    }
}
