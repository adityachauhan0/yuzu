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
    public static let evalModelIdentifier = "alibaba:qwen3.5:0.8b:mirai:mirai-m:4"

    private let gate: TurnGate
    private let cache = CacheGeneration()

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
        return AsyncThrowingStream { continuation in
            let task = Task {
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
    private let engine: Engine
    private let model: Model
    private var session: ChatSession?
    private var epochID: String?
    private var tools: [ToolDefinition] = []
    private var contextLength: Int?
    private var appliedGeneration: UInt64 = 0

    init(engine: Engine, model: Model) {
        self.engine = engine
        self.model = model
    }

    func run(
        _ request: TurnRequest,
        generation: UInt64,
        yield: @Sendable (TurnEvent) -> Void
    ) async throws {
        let includeTools = try await prepare(request, generation: generation)
        let messages = try messages(for: request, includeTools: includeTools)
        // Greedy keeps the small eval model on the tool call instead of a prose echo.
        let config = ChatReplyConfig.create()
            .withSamplingMethod(samplingMethod: .greedy)
            .withToolTurnLimit(toolTurnLimit: 0)
        guard let session else {
            throw UzuTurnError.session("Chat session was not created")
        }
        let stream = await session.replyWithStream(input: messages, config: config)
        var latest: ChatMessage?
        var stats: ChatReplyStats?
        var textSent = ""
        var reasoningSent = ""
        for try await chunk in stream.iterator() {
            try Task.checkCancellation()
            switch chunk {
            case .replies(let replies):
                guard let reply = replies.last else { continue }
                latest = reply.message
                stats = reply.stats
                textSent = emitDelta(reply.message.text() ?? "", sent: textSent) { yield(.text($0)) }
                reasoningSent = emitDelta(reply.message.reasoning() ?? "", sent: reasoningSent) {
                    yield(.reasoning($0))
                }
            case .error(let error):
                throw UzuTurnError.session(String(describing: error))
            }
        }
        guard let latest else {
            throw UzuTurnError.emptyReply
        }
        yield(.finished(assistantTurn(from: latest, stats: stats)))
    }

    private func prepare(_ request: TurnRequest, generation: UInt64) async throws -> Bool {
        let toolsChanged = tools != request.tools
        let epochChanged = epochID != request.epochID
        let generationChanged = generation != appliedGeneration
        let contextChanged = contextLength != request.contextLength
        var includeTools = false

        if session == nil || contextChanged {
            session = try await engine.chat(model: model, config: chatConfig(request.contextLength))
            contextLength = request.contextLength
            includeTools = true
        } else if generationChanged || epochChanged || toolsChanged {
            try await session?.reset()
            includeTools = true
        }

        appliedGeneration = generation
        epochID = request.epochID
        tools = request.tools
        return includeTools
    }

    private func chatConfig(_ contextLength: Int) -> ChatConfig {
        let length: ContextLength = contextLength > 0
            ? .custom(length: Int64(contextLength))
            : .default
        return ChatConfig.create().withContextLength(contextLength: length)
    }

    private func messages(for request: TurnRequest, includeTools: Bool) throws -> [ChatMessage] {
        var systems: [ChatMessage] = []
        var rest: [ChatMessage] = []
        for message in request.delta {
            let converted = try chatMessage(message, effort: request.reasoningEffort)
            if message.role == .system {
                systems.append(converted)
            } else {
                rest.append(converted)
            }
        }
        if includeTools {
            if systems.isEmpty {
                systems.append(
                    ChatMessage.system().withReasoningEffort(
                        reasoningEffort: engineEffort(request.reasoningEffort)
                    )
                )
            }
            systems.append(try toolNamespaceMessage(request.tools))
        }
        return systems + rest
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

    private func chatMessage(
        _ message: StoredMessage,
        effort: YuzuHarness.ReasoningEffort
    ) throws -> ChatMessage {
        switch message.role {
        case .system:
            var chat = ChatMessage.system()
            if !message.text.isEmpty {
                chat = chat.withText(text: message.text)
            }
            return chat.withReasoningEffort(reasoningEffort: engineEffort(effort))
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

    private func engineEffort(_ effort: YuzuHarness.ReasoningEffort) -> Uzu.ReasoningEffort {
        switch effort {
        case .disabled: .disabled
        case .default: .default
        case .low: .low
        case .medium: .medium
        case .high: .high
        case .xHigh: .xHigh
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
