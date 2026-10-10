import Foundation

/// JSON passed through tool arguments and tool schemas.
public enum JSONValue: Sendable, Equatable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

public struct ToolDefinition: Sendable, Equatable, Codable {
    public var name: String
    public var description: String
    public var parameters: JSONValue

    public init(name: String, description: String, parameters: JSONValue) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

public struct ToolCall: Sendable, Equatable, Codable {
    public var id: String
    public var name: String
    public var arguments: JSONValue

    public init(id: String, name: String, arguments: JSONValue) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

public struct AssistantTurn: Sendable, Equatable, Codable {
    public var text: String
    public var reasoning: String
    public var toolCalls: [ToolCall]
    public var outputTokens: Int?

    public init(
        text: String,
        reasoning: String = "",
        toolCalls: [ToolCall] = [],
        outputTokens: Int? = nil
    ) {
        self.text = text
        self.reasoning = reasoning
        self.toolCalls = toolCalls
        self.outputTokens = outputTokens
    }
}

/// One stored transcript row. Session and permission types stay out of this slice.
public struct StoredMessage: Sendable, Equatable, Codable {
    public enum Role: String, Sendable, Equatable, Codable {
        case system
        case developer
        case user
        case assistant
        case tool
    }

    public var role: Role
    public var text: String
    public var reasoning: String
    public var toolCalls: [ToolCall]
    public var toolCallID: String?
    public var toolName: String?
    public var outputTokens: Int?

    public init(
        role: Role,
        text: String = "",
        reasoning: String = "",
        toolCalls: [ToolCall] = [],
        toolCallID: String? = nil,
        toolName: String? = nil,
        outputTokens: Int? = nil
    ) {
        self.role = role
        self.text = text
        self.reasoning = reasoning
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.outputTokens = outputTokens
    }

    public static func system(_ text: String) -> StoredMessage {
        StoredMessage(role: .system, text: text)
    }

    public static func user(_ text: String) -> StoredMessage {
        StoredMessage(role: .user, text: text)
    }

    public static func assistant(_ turn: AssistantTurn) -> StoredMessage {
        StoredMessage(
            role: .assistant,
            text: turn.text,
            reasoning: turn.reasoning,
            toolCalls: turn.toolCalls,
            outputTokens: turn.outputTokens
        )
    }

    public static func toolResult(id: String, name: String, text: String) -> StoredMessage {
        StoredMessage(role: .tool, text: text, toolCallID: id, toolName: name)
    }
}

public enum ReasoningEffort: String, Sendable, Equatable, Codable {
    case disabled
    case `default`
    case low
    case medium
    case high
    case xHigh
}

public struct TurnRequest: Sendable {
    public var epochID: String
    public var delta: [StoredMessage]
    public var tools: [ToolDefinition]
    /// Harness turns send 0. `UzuTurn` also forces 0 on the engine config.
    public var toolTurnLimit: UInt32
    public var reasoningEffort: ReasoningEffort
    public var contextLength: Int

    public init(
        epochID: String,
        delta: [StoredMessage],
        tools: [ToolDefinition],
        toolTurnLimit: UInt32 = 0,
        reasoningEffort: ReasoningEffort,
        contextLength: Int
    ) {
        self.epochID = epochID
        self.delta = delta
        self.tools = tools
        self.toolTurnLimit = toolTurnLimit
        self.reasoningEffort = reasoningEffort
        self.contextLength = contextLength
    }
}

public enum TurnEvent: Sendable {
    case text(String)
    case reasoning(String)
    /// Running totals from the engine. `output` counts every generated token, including reasoning.
    /// `duration` includes prompt prefill. `generateTokensPerSecond` is the decode rate:
    /// (output − 1) / (time of last token − time of first token). That excludes prefill.
    case usage(input: Int, cached: Int, output: Int, duration: Double, generateTokensPerSecond: Double?)
    case finished(AssistantTurn)
}

public struct LiveGeneration: Sendable, Equatable {
    public var inputTokens: Int
    public var cachedTokens: Int
    public var outputTokens: Int
    public var duration: Double
    /// Decode tokens per second. Nil until at least two output tokens exist.
    public var generateTokensPerSecond: Double?

    public var totalTokens: Int { inputTokens + cachedTokens + outputTokens }

    public init(
        inputTokens: Int,
        cachedTokens: Int,
        outputTokens: Int,
        duration: Double,
        generateTokensPerSecond: Double? = nil
    ) {
        self.inputTokens = inputTokens
        self.cachedTokens = cachedTokens
        self.outputTokens = outputTokens
        self.duration = duration
        self.generateTokensPerSecond = generateTokensPerSecond
    }
}

/// What sits behind a turn. A string on screen is not this.
public enum ModelBacking: String, Sendable, Equatable {
    /// Canned turns. Renaming the display label does not change this.
    case scripted
    /// The uzu engine. The enum case alone is not proof of a reply.
    case uzu
}

public protocol ModelTurn: AnyObject, Sendable {
    var backing: ModelBacking { get }
    func complete(_ request: TurnRequest) -> AsyncThrowingStream<TurnEvent, Error>
    func reset(epochID: String)
}
