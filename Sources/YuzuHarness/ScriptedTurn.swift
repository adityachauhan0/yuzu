import Foundation

/// Test double that returns scripted assistant turns, one per `complete` call.
public final class ScriptedTurn: ModelTurn, @unchecked Sendable {
    private let lock = NSLock()
    private var turns: [AssistantTurn]
    private var turnIndex = 0

    public private(set) var requests: [TurnRequest] = []
    public private(set) var resetEpochs: [String] = []
    /// Number of `complete` calls recorded when each `reset` ran (tests).
    public private(set) var resetWhenRequestCount: [Int] = []

    public private(set) var completeIntervals: [(start: Date, end: Date)] = []
    private var activeCompleteStart: Date?

    public var holdBeforeComplete = false
    public var holdAfterFinished = false
    private var holdWaiters: [CheckedContinuation<Void, Never>] = []

    public init(turns: [AssistantTurn]) {
        self.turns = turns
    }

    public func releaseHold() {
        lock.lock()
        let waiters = holdWaiters
        holdWaiters = []
        lock.unlock()
        for waiter in waiters {
            waiter.resume()
        }
    }

    public func complete(_ request: TurnRequest) -> AsyncThrowingStream<TurnEvent, Error> {
        lock.lock()
        requests.append(request)
        lock.unlock()

        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                self.markCompleteStarted()
                if self.holdBeforeComplete {
                    await self.waitForHoldRelease()
                }
                let turn = self.dequeueTurn()
                if !turn.reasoning.isEmpty {
                    continuation.yield(.reasoning(turn.reasoning))
                }
                if !turn.text.isEmpty {
                    continuation.yield(.text(turn.text))
                }
                continuation.yield(.finished(turn))
                if self.holdAfterFinished {
                    await self.waitForHoldRelease()
                }
                self.markCompleteEnded()
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func reset(epochID: String) {
        lock.lock()
        resetEpochs.append(epochID)
        resetWhenRequestCount.append(requests.count)
        lock.unlock()
    }

    private func dequeueTurn() -> AssistantTurn {
        lock.lock()
        defer { lock.unlock() }
        if turnIndex < turns.count {
            let turn = turns[turnIndex]
            turnIndex += 1
            return turn
        }
        return AssistantTurn(text: "")
    }

    private func waitForHoldRelease() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            holdWaiters.append(continuation)
            lock.unlock()
        }
    }

    private func markCompleteStarted() {
        lock.lock()
        activeCompleteStart = Date()
        lock.unlock()
    }

    private func markCompleteEnded() {
        lock.lock()
        if let start = activeCompleteStart {
            completeIntervals.append((start: start, end: Date()))
            activeCompleteStart = nil
        }
        lock.unlock()
    }

    public static func intervalsOverlap(_ intervals: [(start: Date, end: Date)]) -> Bool {
        let sorted = intervals.sorted { $0.start < $1.start }
        for index in 1..<sorted.count {
            if sorted[index].start < sorted[index - 1].end {
                return true
            }
        }
        return false
    }
}
