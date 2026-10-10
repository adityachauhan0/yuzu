import Foundation

/// One step of the session's plan, written by the model with `todowrite`.
public struct TodoItem: Sendable, Equatable, Codable {
    public enum Status: String, Sendable, Codable {
        case pending
        case inProgress = "in_progress"
        case completed
    }

    public var content: String
    public var status: Status

    public init(content: String, status: Status) {
        self.content = content
        self.status = status
    }
}

public enum TodoTool {
    public static let definition = ToolDefinition(
        name: "todowrite",
        description: "Replace this task's step list. Send every step each time, with its status: pending, in_progress or completed.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "todos": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "content": .object(["type": .string("string")]),
                            "status": .object([
                                "type": .string("string"),
                                "enum": .array([.string("pending"), .string("in_progress"), .string("completed")]),
                            ]),
                        ]),
                        "required": .array([.string("content"), .string("status")]),
                    ]),
                ]),
            ]),
            "required": .array([.string("todos")]),
        ])
    )

    /// `nil` when the arguments are not a list of steps.
    public static func parse(_ arguments: JSONValue) -> [TodoItem]? {
        guard case .object(let fields) = arguments, case .array(let entries)? = fields["todos"] else { return nil }
        var items: [TodoItem] = []
        for entry in entries {
            guard case .object(let item) = entry,
                  case .string(let content)? = item["content"],
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            var status = TodoItem.Status.pending
            if case .string(let raw)? = item["status"] {
                guard let parsed = TodoItem.Status(rawValue: raw) else { return nil }
                status = parsed
            }
            items.append(TodoItem(content: content, status: status))
        }
        return items
    }

    public static func summary(_ items: [TodoItem]) -> String {
        let done = items.filter { $0.status == .completed }.count
        return "Updated tasks: \(done) of \(items.count) done."
    }
}
