import Foundation
import Testing
@testable import YuzuHarness

struct TurnTests {
    @Test func toolTurnLimitDefaultsToZero() {
        let request = TurnRequest(
            epochID: "epoch",
            delta: [.user("ping")],
            tools: [],
            reasoningEffort: .disabled,
            contextLength: 1024
        )
        #expect(request.toolTurnLimit == 0)
    }

    @Test func jsonValueRoundTripsToolArguments() throws {
        let value = JSONValue.object(["text": .string("ping")])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == value)
    }
}
