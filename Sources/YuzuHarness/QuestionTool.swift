import Foundation

public enum QuestionTool {
    public static let definition = ToolDefinition(
        name: "question",
        description: "Ask the user one question and wait for their answer.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "question": .object([
                    "type": .string("string"),
                    "description": .string("The question to ask"),
                ]),
            ]),
            "required": .array([.string("question")]),
        ])
    )

    public actor Broker {
        public static let shared = Broker()

        private struct Pending {
            var question: String
            var continuation: CheckedContinuation<String, Never>?
        }

        private var pending: [String: Pending] = [:]
        private var earlyAnswers: [String: String] = [:]

        private func key(sessionID: String, callID: String) -> String {
            "\(sessionID):\(callID)"
        }

        public func register(sessionID: String, callID: String, question: String) async -> String {
            let id = key(sessionID: sessionID, callID: callID)
            if let early = earlyAnswers.removeValue(forKey: id) {
                return early
            }
            return await withCheckedContinuation { continuation in
                pending[id] = Pending(question: question, continuation: continuation)
            }
        }

        public func answer(sessionID: String, callID: String, text: String) {
            let id = key(sessionID: sessionID, callID: callID)
            guard let entry = pending.removeValue(forKey: id) else {
                earlyAnswers[id] = text
                return
            }
            entry.continuation?.resume(returning: text)
        }

        public func pendingQuestions(sessionID: String) -> [(callID: String, question: String)] {
            pending.compactMap { key, value in
                guard key.hasPrefix("\(sessionID):") else { return nil }
                let callID = String(key.dropFirst(sessionID.count + 1))
                return (callID, value.question)
            }
        }

        public func cancel(sessionID: String, callID: String) {
            let id = key(sessionID: sessionID, callID: callID)
            if let entry = pending.removeValue(forKey: id) {
                entry.continuation?.resume(returning: "Question dismissed")
            }
        }
    }

    public static func questionText(from arguments: JSONValue) -> String? {
        stringField(arguments, key: "question")?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
