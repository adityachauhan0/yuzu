import Foundation
import Uzu
import YuzuHarness

public enum UzuTurnError: Error, Equatable, Sendable {
    case modelUnavailable(String)
    case downloadFailed(String)
    case emptyReply
    case session(String)
}

/// The only type that imports `Uzu`. Tool schemas travel as a developer message.
/// This type never calls `addTool` or `addForeignTool`.
public final class UzuTurn: ModelTurn, @unchecked Sendable {
    public let backing: ModelBacking = .uzu
    public static let evalModelIdentifier = "alibaba:qwen3.5:0.8b:mirai:mirai-m:4"
    /// What every reply asks the engine to sample with. Settings shows this for the loaded model.
    fileprivate static let sampling = SamplingMethod.greedy
    public static var samplingLabel: String {
        switch sampling {
        case .greedy: "greedy"
        case .stochastic: "stochastic"
        }
    }

    private let gate: TurnGate
    private let cache = CacheGeneration()
    private let turns = TurnQueue()

    init(engine: Engine, model: Model) {
        self.gate = TurnGate(engine: engine, model: model)
    }

    /// Loads the eval model when the engine catalog returns it, downloading if needed.
    public static func makeEvalTurn() async throws -> UzuTurn {
        let engine = try await Engine.create(config: .create())
        guard let model = try await engine.model(identifier: evalModelIdentifier) else {
            throw UzuTurnError.modelUnavailable(evalModelIdentifier)
        }
        print("UzuTurn eval model: \(model.identifier)")
        let download = try await engine.download(model: model)
        var lastPrinted = -1
        for try await update in download.iterator() {
            if case .error(let message) = update.phase {
                throw UzuTurnError.downloadFailed(message)
            }
            let percent = Int(update.progress() * 100)
            if percent != lastPrinted, percent.isMultiple(of: 5) || update.phase == .downloaded {
                print("UzuTurn download \(percent)% \(update.phase)")
                lastPrinted = percent
            }
        }
        print("UzuTurn download finished")
        return UzuTurn(engine: engine, model: model)
    }

    public func complete(_ request: TurnRequest) -> AsyncThrowingStream<TurnEvent, Error> {
        let gate = self.gate
        let generation = cache.current
        let turns = self.turns
        return AsyncThrowingStream { continuation in
            let task = turns.enqueue {
                do {
                    try await gate.run(request, generation: generation) { event in
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func reset(epochID _: String) {
        cache.invalidate()
    }
}

/// A cancelled consumer returns before the engine stream drains, and `TurnGate` is
/// reentrant across awaits, so each turn starts only after the previous one ends.
private final class TurnQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var last: Task<Void, Never>?

    func enqueue(_ body: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        lock.lock()
        defer { lock.unlock() }
        let previous = last
        let task = Task {
            await previous?.value
            await body()
        }
        last = task
        return task
    }
}

private final class CacheGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0

    var current: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    func invalidate() {
        lock.lock()
        generation += 1
        lock.unlock()
    }
}

private actor TurnGate {
    private enum Start {
        /// The session already holds everything before this delta.
        case warm
        /// The harness rewound its cursor; the delta carries the whole epoch.
        case clean
        /// The session was rebuilt mid-epoch; replay what it held before.
        case replay
    }

    private let engine: Engine
    private let model: Model
    private var session: ChatSession?
    private var epochID: String?
    private var tools: [ToolDefinition] = []
    private var contextLength: Int?
    private var effort: Uzu.ReasoningEffort?
    private var appliedGeneration: UInt64 = 0
    private var broken = false
    private var leadingSystem: String?
    /// Everything after the leading system message that this epoch's session has accepted.
    private var transcript: [StoredMessage] = []

    init(engine: Engine, model: Model) {
        self.engine = engine
        self.model = model
    }

    func run(
        _ request: TurnRequest,
        generation: UInt64,
        yield: @Sendable (TurnEvent) -> Void
    ) async throws {
        let start = try await prepare(request, generation: generation)
        let (messages, accepted) = try messages(for: request, start: start)
        // Greedy keeps the small eval model on the tool call instead of a prose echo.
        let config = ChatReplyConfig.create()
            .withSamplingMethod(samplingMethod: UzuTurn.sampling)
            .withToolTurnLimit(toolTurnLimit: 0)
        guard let session else {
            throw UzuTurnError.session("Chat session was not created")
        }
        broken = true
        let stream = await session.replyWithStream(input: messages, config: config)
        var latest: ChatMessage?
        var stats: ChatReplyStats?
        var textSent = ""
        var reasoningSent = ""
        var reportedInput = -1
        var reportedCached = -1
        var reportedOutput = -1
        // Cancelling stops sampling; the stream still runs to its end so the session
        // leaves the generation state before the next reset.
        try await withTaskCancellationHandler {
            for try await chunk in stream.iterator() {
                switch chunk {
                case .replies(let replies):
                    guard let reply = replies.last, !Task.isCancelled else { continue }
                    latest = reply.message
                    stats = reply.stats
                    textSent = emitDelta(reply.message.text() ?? "", sent: textSent) { yield(.text($0)) }
                    reasoningSent = emitDelta(reply.message.reasoning() ?? "", sent: reasoningSent) {
                        yield(.reasoning($0))
                    }
                    let input = Int(reply.stats.tokensCountInput ?? 0)
                    let cached = Int(reply.stats.tokensCountInputCached ?? 0)
                    let output = Int(reply.stats.tokensCountOutput ?? 0)
                    if input != reportedInput || cached != reportedCached || output != reportedOutput {
                        reportedInput = input
                        reportedCached = cached
                        reportedOutput = output
                        yield(.usage(
                            input: input,
                            cached: cached,
                            output: output,
                            duration: reply.stats.duration
                        ))
                    }
                case .error(let error):
                    if Task.isCancelled { continue }
                    throw UzuTurnError.session(String(describing: error))
                }
            }
        } onCancel: {
            stream.cancelToken().cancel()
        }
        try Task.checkCancellation()
        guard let latest else {
            throw UzuTurnError.emptyReply
        }
        let turn = assistantTurn(from: latest, stats: stats)
        transcript.append(contentsOf: accepted)
        transcript.append(.assistant(turn))
        broken = false
        yield(.finished(turn))
    }

    private func prepare(_ request: TurnRequest, generation: UInt64) async throws -> Start {
        let wantedEffort = engineEffort(request.reasoningEffort)
        let rewound = epochID != request.epochID || generation != appliedGeneration
        let rebuilt = broken
            || tools != request.tools
            || effort != wantedEffort
            || contextLength != request.contextLength

        var start = Start.warm
        if session == nil || contextLength != request.contextLength {
            let created = session == nil
            session = try await engine.chat(model: model, config: chatConfig(request.contextLength))
            start = rewound || created ? .clean : .replay
        } else if let current = session, rewound || rebuilt {
            if await settled(current) {
                try await current.reset()
            } else {
                session = try await engine.chat(model: model, config: chatConfig(request.contextLength))
            }
            start = rewound ? .clean : .replay
        }
        if transcript.isEmpty, leadingSystem == nil, start == .replay {
            start = .clean
        }
        if start == .clean, epochID != request.epochID {
            leadingSystem = nil
        }

        appliedGeneration = generation
        epochID = request.epochID
        tools = request.tools
        effort = wantedEffort
        contextLength = request.contextLength
        broken = false
        return start
    }

    /// A cancelled stream can end before the session leaves `generation`, and `reset` refuses until it does.
    private func settled(_ session: ChatSession) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(30)
        while await session.state() != .idle {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    private func chatConfig(_ contextLength: Int) -> ChatConfig {
        let length: ContextLength = contextLength > 0
            ? .custom(length: Int64(contextLength))
            : .default
        return ChatConfig.create().withContextLength(contextLength: length)
    }

    /// Returns the input for the session and the delta messages it will hold after a reply.
    private func messages(for request: TurnRequest, start: Start) throws -> ([ChatMessage], [StoredMessage]) {
        // The session keeps every message it was sent, and Qwen's template rejects a
        // system message anywhere but first. Only a fresh session gets one; later
        // system text is delivered as a user-side reminder, which every role accepts next.
        var delta = request.delta[...]
        if let first = delta.first, first.role == .system {
            if start == .clean {
                leadingSystem = first.text
                delta = delta.dropFirst()
            } else if first.text == leadingSystem {
                delta = delta.dropFirst()
            }
        }

        var messages: [ChatMessage] = []
        var history: [StoredMessage] = []
        switch start {
        case .warm:
            break
        case .clean:
            transcript = []
            messages.append(leadingSystemMessage())
            messages.append(try toolNamespaceMessage(request.tools))
        case .replay:
            messages.append(leadingSystemMessage())
            messages.append(try toolNamespaceMessage(request.tools))
            history = transcript
        }
        for message in history + delta {
            switch message.role {
            case .system, .developer:
                if !message.text.isEmpty {
                    messages.append(ChatMessage.user().withText(text: "<system-reminder>\n\(message.text)\n</system-reminder>"))
                }
            case .user, .assistant, .tool:
                messages.append(try chatMessage(message))
            }
        }
        return (messages, Array(delta))
    }

    private func leadingSystemMessage() -> ChatMessage {
        var message = ChatMessage.system().withReasoningEffort(reasoningEffort: effort ?? .default)
        if let leadingSystem, !leadingSystem.isEmpty {
            message = message.withText(text: leadingSystem)
        }
        return message
    }

    private func toolNamespaceMessage(_ tools: [ToolDefinition]) throws -> ChatMessage {
        let descriptions = try tools.map { tool -> ToolDescription in
            .function(
                toolFunction: ToolFunction(
                    name: tool.name,
                    description: tool.description,
                    parameters: Value(json: try jsonText(tool.parameters)),
                    returnDefinition: nil
                )
            )
        }
        let namespace = ToolNamespace(name: "yuzu", description: nil, tools: descriptions)
        return ChatMessage.developer().withToolNamespaces(toolNamespaces: [namespace])
    }

    private func chatMessage(_ message: StoredMessage) throws -> ChatMessage {
        switch message.role {
        case .system:
            var chat = ChatMessage.system()
            if !message.text.isEmpty {
                chat = chat.withText(text: message.text)
            }
            return chat
        case .developer:
            var chat = ChatMessage.developer()
            if !message.text.isEmpty {
                chat = chat.withText(text: message.text)
            }
            return chat
        case .user:
            return ChatMessage.user().withText(text: message.text)
        case .assistant:
            var chat = ChatMessage.assistant()
            if !message.text.isEmpty {
                chat = chat.withText(text: message.text)
            }
            if !message.reasoning.isEmpty {
                chat = chat.withReasoning(reasoning: message.reasoning)
            }
            for call in message.toolCalls {
                chat = chat.withToolCall(
                    toolCall: Uzu.ToolCall(
                        identifier: call.id.isEmpty ? nil : call.id,
                        name: call.name,
                        arguments: Value(json: try jsonText(call.arguments))
                    )
                )
            }
            return chat
        case .tool:
            let identifier = message.toolCallID.flatMap { $0.isEmpty ? nil : $0 }
            let name = message.toolName.flatMap { $0.isEmpty ? nil : $0 }
            return ChatMessage.tool().withBlock(
                block: .toolCallResult(
                    identifier: identifier,
                    name: name,
                    value: Value(json: try jsonText(.string(message.text)))
                )
            )
        }
    }

    private func assistantTurn(from message: ChatMessage, stats: ChatReplyStats?) -> AssistantTurn {
        let calls = message.toolCalls().enumerated().map { index, call in
            YuzuHarness.ToolCall(
                id: call.identifier.flatMap { $0.isEmpty ? nil : $0 } ?? "call-\(index)",
                name: call.name,
                arguments: jsonValue(call.arguments.json)
            )
        }
        return AssistantTurn(
            text: message.text() ?? "",
            reasoning: message.reasoning() ?? "",
            toolCalls: calls,
            outputTokens: stats?.tokensCountOutput.map(Int.init)
        )
    }

    /// Qwen's renderer maps only `disabled` and `default` to `enable_thinking`; any other value fails the render.
    /// So Low answers without thinking, and Medium and above think.
    private func engineEffort(_ effort: YuzuHarness.ReasoningEffort) -> Uzu.ReasoningEffort {
        switch effort {
        case .disabled, .low: return .disabled
        case .medium, .high, .xHigh, .default: return .default
        }
    }

    private func jsonText(_ value: JSONValue) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    private func jsonValue(_ json: String) -> JSONValue {
        guard let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return .string(json)
        }
        return value
    }

    private func emitDelta(
        _ next: String,
        sent: String,
        yield: (String) -> Void
    ) -> String {
        guard next != sent else { return sent }
        if next.hasPrefix(sent) {
            let delta = String(next.dropFirst(sent.count))
            if !delta.isEmpty {
                yield(delta)
            }
            return next
        }
        yield(next)
        return next
    }
}
