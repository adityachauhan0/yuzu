import Foundation

public struct CompactionSettings: Sendable, Equatable {
    public var contextLength: Int
    public var bufferTokens: Int
    public var keepTokens: Int

    public static let production = CompactionSettings(
        contextLength: 32_768,
        bufferTokens: 20_000,
        keepTokens: 8_000
    )

    public init(contextLength: Int, bufferTokens: Int, keepTokens: Int) {
        self.contextLength = contextLength
        self.bufferTokens = bufferTokens
        self.keepTokens = keepTokens
    }

    public init(session: SessionRecord) {
        self.init(
            contextLength: session.contextLength,
            bufferTokens: session.compactionBufferTokens,
            keepTokens: session.compactionKeepTokens
        )
    }
}

public struct CompactionSelection: Sendable, Equatable {
    public var head: [StoredMessage]
    public var tail: [StoredMessage]
    public var tailStartOrdinal: Int
}

public enum Compaction {
    public static let summaryOutputTokenCap = 4_096
    public static let toolOutputMaxChars = 2_000
    public static let summaryInstruction = "Create a new anchored summary from the conversation history"

    private static let summaryTemplate = """
    Output exactly the Markdown structure shown inside and keep the section order unchanged. Do not include the tags in your response.

    ## Goal

    ## Constraints & Preferences

    ## Progress
    ### Done
    ### In Progress
    ### Blocked

    ## Key Decisions

    ## Next Steps

    ## Critical Context

    ## Relevant Files

    Rules:
    - Keep every section, even when empty.
    - Use terse bullets, not prose paragraphs.
    - Preserve exact file paths, commands, error strings, and identifiers when known.
    - Do not mention the summary process or that context was compacted.
    """

    public static func needsCompaction(
        projected: [StoredMessage],
        baseline: String?,
        settings: CompactionSettings
    ) -> Bool {
        let tokens = estimateTokens(messages: projected, baseline: baseline)
        return tokens + settings.bufferTokens > settings.contextLength
    }

    public static func selectMessages(
        messages: [StoredMessage],
        settings: CompactionSettings
    ) -> CompactionSelection {
        guard !messages.isEmpty else {
            return CompactionSelection(head: [], tail: [], tailStartOrdinal: 0)
        }

        var tailCount = 0
        var tailTokens = 0
        for index in messages.indices.reversed() {
            let messageTokens = estimateTokens(messages: [messages[index]], baseline: nil)
            if tailCount > 0, tailTokens + messageTokens > settings.keepTokens {
                break
            }
            tailTokens += messageTokens
            tailCount += 1
        }

        if tailCount == messages.count {
            let split = max(1, messages.count - 1)
            return CompactionSelection(
                head: Array(messages.prefix(split)),
                tail: Array(messages.suffix(messages.count - split)),
                tailStartOrdinal: split
            )
        }

        let start = messages.count - tailCount
        return CompactionSelection(
            head: Array(messages.prefix(start)),
            tail: Array(messages.suffix(tailCount)),
            tailStartOrdinal: start
        )
    }

    public static func buildSummaryPrompt(
        head: [StoredMessage],
        previousSummary: String?
    ) -> String {
        let conversation = head.map(serializeForSummary).joined(separator: "\n\n")
        let anchor: String
        if let previousSummary, !previousSummary.isEmpty {
            anchor = """
            Update the anchored summary below using the conversation history above.
            Preserve still-true details, remove stale details, and merge in the new facts.

            \(previousSummary)
            """
        } else {
            anchor = summaryInstruction
        }
        return [anchor, summaryTemplate, conversation].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    public static func isSummaryTurnRequest(_ request: TurnRequest) -> Bool {
        request.tools.isEmpty
            && request.delta.contains { message in
                message.role == .user && message.text.contains(summaryInstruction)
            }
    }

    public static func projectedHistory(
        messages: [StoredMessage],
        epochID: String,
        messageEpochIDs: [String],
        compactionSummary: String?,
        tailStartOrdinal: Int
    ) -> [StoredMessage] {
        var visible = messages.enumerated().compactMap { index, message -> StoredMessage? in
            if index < tailStartOrdinal {
                return nil
            }
            if message.role == .system, messageEpochIDs.indices.contains(index) {
                let messageEpoch = messageEpochIDs[index]
                if !messageEpoch.isEmpty, messageEpoch != epochID {
                    return nil
                }
            }
            return message
        }

        if let compactionSummary, !compactionSummary.isEmpty {
            visible.insert(.user(compactionSummary), at: 0)
        }
        return visible
    }

    public static func estimateTokens(messages: [StoredMessage], baseline: String?) -> Int {
        var chars = 0
        if let baseline {
            chars += baseline.utf8.count
        }
        for message in messages {
            chars += serializedLength(message)
        }
        return max(1, chars / 4)
    }

    private static func serializedLength(_ message: StoredMessage) -> Int {
        serializeForSummary(message).utf8.count
    }

    private static func serializeForSummary(_ message: StoredMessage) -> String {
        switch message.role {
        case .user:
            return "[User]: \(message.text)"
        case .assistant:
            var parts: [String] = []
            if !message.text.isEmpty {
                parts.append("[Assistant]: \(message.text)")
            }
            if !message.reasoning.isEmpty {
                parts.append("[Assistant reasoning]: \(message.reasoning)")
            }
            for call in message.toolCalls {
                parts.append("[Assistant tool call]: \(call.name)(\(call.arguments))")
            }
            return parts.joined(separator: "\n")
        case .tool:
            let output = truncateToolOutput(message.text)
            return "[Tool result]: \(output)"
        case .system:
            return "[System]: \(message.text)"
        case .developer:
            return "[Developer]: \(message.text)"
        }
    }

    private static func truncateToolOutput(_ text: String) -> String {
        if text.count <= toolOutputMaxChars {
            return text
        }
        return String(text.prefix(toolOutputMaxChars)) + "\n[truncated]"
    }
}
