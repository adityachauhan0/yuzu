import Testing

/// `MCPHub.shared` feeds every runner's tools and context. Suites that connect servers
/// hold it exclusively; suites that only read it share it, so parallel runs stay deterministic.
struct MCPHubAccess: SuiteTrait, TestTrait, TestScoping {
    let exclusive: Bool

    var isRecursive: Bool { true }

    func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
        test.isSuite || testCase == nil ? nil : self
    }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        await HubGate.shared.acquire(exclusive: exclusive)
        do {
            try await function()
        } catch {
            await HubGate.shared.release(exclusive: exclusive)
            throw error
        }
        await HubGate.shared.release(exclusive: exclusive)
    }
}

extension Trait where Self == MCPHubAccess {
    static var readsMCPHub: Self { MCPHubAccess(exclusive: false) }
    static var ownsMCPHub: Self { MCPHubAccess(exclusive: true) }
}

private actor HubGate {
    static let shared = HubGate()

    private var readers = 0
    private var writer = false
    private var queue: [(exclusive: Bool, resume: CheckedContinuation<Void, Never>)] = []

    func acquire(exclusive: Bool) async {
        if queue.isEmpty, canGrant(exclusive: exclusive) {
            grant(exclusive: exclusive)
            return
        }
        await withCheckedContinuation { queue.append((exclusive, $0)) }
    }

    func release(exclusive: Bool) {
        if exclusive { writer = false } else { readers -= 1 }
        while let next = queue.first, canGrant(exclusive: next.exclusive) {
            queue.removeFirst()
            grant(exclusive: next.exclusive)
            next.resume.resume()
        }
    }

    private func canGrant(exclusive: Bool) -> Bool {
        exclusive ? !writer && readers == 0 : !writer
    }

    private func grant(exclusive: Bool) {
        if exclusive { writer = true } else { readers += 1 }
    }
}
