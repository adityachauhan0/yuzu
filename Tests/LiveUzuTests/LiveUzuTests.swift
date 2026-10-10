import Foundation
import Testing
import YuzuHarness
import YuzuModel

@Suite(.serialized)
struct LiveUzuTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["YUZU_EVAL_MODEL"] == "1"))
    func U1_unregisteredToolCallReturns() async throws {
        let finished = try await EvalModel.shared.run { turn in
            try await finish(echoRequest(epochID: "u1"), on: turn)
        }
        print("U1 \(describe(finished))")
        let call = finished.toolCalls.first { $0.name == "echo" }
        #expect(
            call?.arguments == echoArguments,
            "echo tool call missing; \(describe(finished))"
        )
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["YUZU_EVAL_MODEL"] == "1"))
    func U1b_toolResultProducesAnswer() async throws {
        let epochID = "u1b"
        let (_, second) = try await EvalModel.shared.run { turn -> (AssistantTurn, AssistantTurn) in
            let first = try await finish(echoRequest(epochID: epochID), on: turn)
            print("U1b first \(describe(first))")
            let call = try #require(
                first.toolCalls.first { $0.name == "echo" && $0.arguments == echoArguments },
                "echo tool call missing before the tool result; \(describe(first))"
            )
            let second = try await finish(
                TurnRequest(
                    epochID: epochID,
                    delta: [.toolResult(id: call.id, name: call.name, text: "pong")],
                    tools: [echoTool],
                    toolTurnLimit: 0,
                    reasoningEffort: .disabled,
                    contextLength: evalContextLength
                ),
                on: turn
            )
            return (first, second)
        }
        print("U1b finished \(describe(second))")
        #expect(second.text.contains("pong"), "finished text was \(second.text)")
        #expect(second.toolCalls.isEmpty)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["YUZU_EVAL_MODEL"] == "1"))
    func U2_toolChangeMidEpochKeepsHistory() async throws {
        let epochID = "u2"
        let codeword = "TANGERINE"
        let answer = try await EvalModel.shared.run { turn -> AssistantTurn in
            _ = try await finish(
                TurnRequest(
                    epochID: epochID,
                    delta: [
                        .system("You are a terse assistant."),
                        .user("My codeword is \(codeword). Reply with only OK."),
                    ],
                    tools: [echoTool],
                    reasoningEffort: .disabled,
                    contextLength: evalContextLength
                ),
                on: turn
            )
            let shout = ToolDefinition(name: "shout", description: "Shout text.", parameters: echoTool.parameters)
            return try await finish(
                TurnRequest(
                    epochID: epochID,
                    delta: [.user("What is my codeword? Reply with only the codeword.")],
                    tools: [echoTool, shout],
                    reasoningEffort: .disabled,
                    contextLength: evalContextLength
                ),
                on: turn
            )
        }
        print("U2 \(describe(answer))")
        #expect(answer.text.uppercased().contains(codeword), "answer was \(answer.text)")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["YUZU_EVAL_MODEL"] == "1"))
    func U3_cancelStopsGenerationAndTheNextTurnAnswers() async throws {
        let epochID = "u3"
        let codeword = "MARIGOLD"
        let (chunks, drained, answer) = try await EvalModel.shared.run { turn -> (Int, TimeInterval, AssistantTurn) in
            var chunks = 0
            let system = StoredMessage.system("You are a terse assistant.")
            let counting = StoredMessage.user("My codeword is \(codeword). Now count from 1 to 2000, one number per line.")
            for try await event in turn.complete(
                TurnRequest(
                    epochID: epochID,
                    delta: [system, counting],
                    tools: [],
                    reasoningEffort: .disabled,
                    contextLength: evalContextLength
                )
            ) {
                if case .text = event { chunks += 1 }
                if case .finished(let first) = event { print("U3 first finished early \(describe(first))") }
                if chunks == 5 { break }
            }
            let cancelled = Date()
            // A cancelled turn leaves the harness cursor in place, so the next delta repeats its input.
            let answer = try await finish(
                TurnRequest(
                    epochID: epochID,
                    delta: [system, counting, .user("Stop counting. What is my codeword? Reply with only the codeword.")],
                    tools: [],
                    reasoningEffort: .disabled,
                    contextLength: evalContextLength
                ),
                on: turn
            )
            return (chunks, Date().timeIntervalSince(cancelled), answer)
        }
        print("U3 chunks=\(chunks) next turn took \(drained)s \(describe(answer))")
        #expect(chunks == 5)
        #expect(drained < 20, "the cancelled generation kept running for \(drained)s")
        #expect(answer.text.uppercased().contains(codeword), "answer was \(answer.text)")
    }
}

private let evalContextLength = 32_768

private let echoArguments = JSONValue.object(["text": .string("ping")])

private let echoTool = ToolDefinition(
    name: "echo",
    description: "Echo the provided text.",
    parameters: .object([
        "type": .string("object"),
        "properties": .object([
            "text": .object([
                "type": .string("string"),
                "description": .string("Text to echo."),
            ]),
        ]),
        "required": .array([.string("text")]),
    ])
)

private func echoRequest(epochID: String) -> TurnRequest {
    TurnRequest(
        epochID: epochID,
        delta: [
            .system("You call the echo tool when asked. Do not answer in prose."),
            .user("""
            Call the echo function now. Reply with only this call:
            <tool_call>
            <function=echo>
            <parameter=text>
            ping
            </parameter>
            </function>
            </tool_call>
            """),
        ],
        tools: [echoTool],
        toolTurnLimit: 0,
        reasoningEffort: .disabled,
        contextLength: evalContextLength
    )
}

private func describe(_ turn: AssistantTurn) -> String {
    let calls = turn.toolCalls.map { call in
        let arguments = (try? JSONEncoder().encode(call.arguments)).map { String(decoding: $0, as: UTF8.self) } ?? "?"
        return "\(call.id) \(call.name) \(arguments)"
    }
    return "text=\(turn.text) reasoning=\(turn.reasoning) toolCalls=\(calls)"
}

private func finish(_ request: TurnRequest, on turn: UzuTurn) async throws -> AssistantTurn {
    var finished: AssistantTurn?
    for try await event in turn.complete(request) {
        if case .finished(let turn) = event {
            finished = turn
        }
    }
    return try #require(finished)
}

private actor EvalModel {
    static let shared = EvalModel()
    private var turn: UzuTurn?

    func run<T: Sendable>(_ body: @Sendable (UzuTurn) async throws -> T) async throws -> T {
        if turn == nil {
            turn = try await UzuTurn.makeEvalTurn()
        }
        guard let turn else {
            throw UzuTurnError.session("Eval model did not load")
        }
        return try await body(turn)
    }
}
