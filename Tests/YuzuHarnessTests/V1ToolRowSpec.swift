import Foundation
@testable import YuzuHarness

/// V1 contract for expandable tool rows (see docs/architecture/16-v1-implementation.md).
enum V1ToolRowSpec {
    struct Row: Equatable, Sendable {
        var title: String
        var detail: String
    }

    static func expectedRow(for call: ToolCall) -> Row {
        switch call.name {
        case "read":
            return Row(title: "Read", detail: stringArg(call.arguments, key: "path") ?? "")
        case "write":
            return Row(title: "Write", detail: stringArg(call.arguments, key: "path") ?? "")
        case "edit":
            return Row(title: "Edit", detail: stringArg(call.arguments, key: "path") ?? "")
        case "bash":
            return Row(title: "Shell", detail: stringArg(call.arguments, key: "command") ?? "")
        case "grep":
            return Row(title: "Grep", detail: stringArg(call.arguments, key: "pattern") ?? "")
        case "glob":
            return Row(title: "Glob", detail: stringArg(call.arguments, key: "pattern") ?? "")
        case "skill":
            let name = stringArg(call.arguments, key: "name") ?? ""
            return Row(title: "Skill", detail: "Loaded \(name)")
        case "task":
            let prompt = stringArg(call.arguments, key: "prompt") ?? ""
            let firstLine = prompt.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? prompt
            return Row(title: "Task", detail: firstLine)
        case TodoTool.definition.name:
            return Row(title: "Todos", detail: "")
        case QuestionTool.definition.name:
            return Row(title: "Question", detail: stringArg(call.arguments, key: "question") ?? "")
        case "webfetch":
            return Row(title: "Web fetch", detail: stringArg(call.arguments, key: "url") ?? "")
        default:
            return Row(title: call.name, detail: "")
        }
    }

    private static func stringArg(_ value: JSONValue, key: String) -> String? {
        guard case .object(let object) = value, case .string(let string) = object[key] else {
            return nil
        }
        return string
    }
}

/// When `ToolActivityFormatter` lands in YuzuHarness, wire it here for parity checks.
enum V1ToolRowFormatterBridge {
    static func format(_ call: ToolCall, result: String? = nil) -> V1ToolRowSpec.Row {
        let row = ToolRowFormatter.present(call: call, result: result)
        return V1ToolRowSpec.Row(title: row.title, detail: row.detail)
    }
}
