import Testing
import YuzuHarness

struct ModelAdviceTests {
    private let sixteenGB: Int64 = 16 * 1024 * 1024 * 1024

    @Test func R3_advicePicksLargestMiraiMThatFits() {
        let tiny = candidate("tiny", params: 800_000_000, bytes: 500_000_000, method: "mirai-m")
        let best = candidate("best", params: 4_000_000_000, bytes: 2_400_000_000, method: "mirai-m")
        let fillsTheMachine = candidate("thirty", params: 30_000_000_000, bytes: 12_000_000_000, method: "mirai-m")
        let tooBig = candidate("huge", params: 70_000_000_000, bytes: 40_000_000_000, method: "mirai-m")
        let biggerButWorseQuant = candidate("mirai-s-big", params: 9_000_000_000, bytes: 5_000_000_000, method: "mirai-s")
        let notChat = candidate("embed", params: 7_000_000_000, bytes: 4_000_000_000, method: "mirai-m", chat: false)

        let advised = ModelAdvice.advise(
            [tooBig, fillsTheMachine, biggerButWorseQuant, tiny, notChat, best],
            memoryTotal: sixteenGB
        )
        #expect(advised?.identifier == "best")
    }

    private func candidate(
        _ id: String,
        params: Int64,
        bytes: Int64,
        method: String,
        chat: Bool = true
    ) -> ModelCandidate {
        ModelCandidate(
            identifier: id,
            name: id,
            parameterCount: params,
            checkpointBytes: bytes,
            quantizationMethod: method,
            bitsPerWeight: 4,
            isChat: chat
        )
    }
}
