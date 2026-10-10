import Foundation
import os

public final class SessionRunner: HarnessClient, @unchecked Sendable {
    private struct RunnerState {
        var runTask: Task<Void, Never>?
        var cancelRequested = false
        var queuePromotionWaiters: [CheckedContinuation<Void, Never>] = []
        var toolSettleWaiters: [CheckedContinuation<Void, Never>] = []
        var providerTurnWaiters: [CheckedContinuation<Void, Never>] = []
        var permissionWaiters: [String: CheckedContinuation<PermissionReply, Never>] = [:]
    }

    public let sessionID: String
    private let store: HarnessStore
    private let model: any ModelTurn
    private let stateLock = OSAllocatedUnfairLock(initialState: RunnerState())

    /// Test hook: block the drain before queue promotion (L1).
    public var holdBeforeQueuePromotion = false
    /// Test hook: block after a model turn returns tool calls, before settlement (L7).
    public var holdBeforeToolSettle = false
    /// Test hook: block immediately before calling the model (L9).
    public var holdBeforeProviderTurn = false

    /// Overrides materialized tool names for the next boundary (tests).
    public var materializeOnly: Set<String>?

    public var contextCoordinator = ContextCoordinator()

    public init(sessionID: String, store: HarnessStore, model: any ModelTurn) {
        self.sessionID = sessionID
        self.store = store
        self.model = model
    }

    public func releaseQueuePromotionHold() {
        let waiters = stateLock.withLock { state -> [CheckedContinuation<Void, Never>] in
            let waiters = state.queuePromotionWaiters
            state.queuePromotionWaiters = []
            return waiters
        }
        for waiter in waiters {
            waiter.resume()
        }
    }

    public func releaseProviderTurnHold() {
        let waiters = stateLock.withLock { state -> [CheckedContinuation<Void, Never>] in
            let waiters = state.providerTurnWaiters
            state.providerTurnWaiters = []
            return waiters
        }
        for waiter in waiters {
            waiter.resume()
        }
    }

    public func releaseToolSettleHold() {
        let waiters = stateLock.withLock { state -> [CheckedContinuation<Void, Never>] in
            let waiters = state.toolSettleWaiters
            state.toolSettleWaiters = []
            return waiters
        }
        for waiter in waiters {
            waiter.resume()
        }
    }

    public func run() async {
        let existing = stateLock.withLock { state -> Task<Void, Never>? in
            if let task = state.runTask {
                return task
            }
            let task = Task { await self.drainLoop() }
            state.runTask = task
            return nil
        }
        if let existing {
            await existing.value
            return
        }
        let task = stateLock.withLock { $0.runTask! }
        await task.value
        stateLock.withLock { state in
            state.runTask = nil
        }
    }

    public func prompt(_ text: String, delivery: Delivery) async {
        _ = try? store.appendInbox(sessionID: sessionID, text: text, delivery: delivery)
        await run()
    }

    public func cancel() async {
        stateLock.withLock { $0.cancelRequested = true }

        if (try? store.deleteLastAssistantIfBareToolCall(sessionID: sessionID)) == true {
            if var session = try? store.session(id: sessionID) {
                session.modelMessageCursor = 0
                try? store.updateSession(session)
                model.reset(epochID: session.epochID)
            }
        }

        stateLock.withLock { $0.cancelRequested = false }
    }

    public func replyPermission(_ id: String, _ reply: PermissionReply) async {
        let waiter = stateLock.withLock { state -> CheckedContinuation<PermissionReply, Never>? in
            state.permissionWaiters.removeValue(forKey: id)
        }
        waiter?.resume(returning: reply)
    }

    public func setManualPressed(_ pressed: Bool) async {
        if var session = try? store.session(id: sessionID) {
            session.manualPressed = pressed
            try? store.updateSession(session)
        }
    }

    public func setAgent(_ id: String) async {
        if var session = try? store.session(id: sessionID) {
            session.agentID = id
            try? store.updateSession(session)
        }
    }

    public func admitSteerDuringSettle(_ text: String) throws {
        _ = try store.appendInbox(sessionID: sessionID, text: text, delivery: .steer)
    }

    private func drainLoop() async {
        guard var session = try? store.session(id: sessionID) else { return }
        session.status = .running
        try? store.updateSession(session)

        loop: while true {
            if let dangling = try? store.danglingToolCall(sessionID: sessionID) {
                await settle(call: dangling, session: session)
                session = (try? store.session(id: sessionID)) ?? session
                if await promoteSteerAtBoundary(session: &session) {
                    continue loop
                }
                continue loop
            }

            if await promoteSteerAtBoundary(session: &session) {
                session = (try? store.session(id: sessionID)) ?? session
            }

            if isCancelRequested() {
                break loop
            }

            guard needsProviderTurn(sessionID: sessionID) else {
                if await promoteQueueAtIdle(session: &session) {
                    session = (try? store.session(id: sessionID)) ?? session
                    continue loop
                }
                break loop
            }

            guard await promoteQueueBeforeTurn(session: &session) else {
                break loop
            }
            session = (try? store.session(id: sessionID)) ?? session

            let contextResult: ContextBoundaryResult
            do {
                contextResult = try contextCoordinator.reconcile(
                    store: store,
                    sessionID: sessionID,
                    epochID: session.epochID,
                    projectPath: session.projectPath
                )
            } catch {
                break loop
            }
            if contextResult.blocked {
                break loop
            }

            let agent = agentFor(session)
            let savedAllows = (try? store.permissionRules(projectPath: session.projectPath)) ?? []
            let materialized = ToolRegistry.materialize(
                agent: agent,
                projectPath: session.projectPath,
                savedAllows: savedAllows,
                manualPressed: session.manualPressed,
                onlyNames: materializeOnly
            )
            materializeOnly = nil

            session = (try? store.session(id: sessionID)) ?? session
            let delta = (try? contextCoordinator.providerDelta(
                store: store,
                sessionID: sessionID,
                session: session
            )) ?? []

            let request = TurnRequest(
                epochID: session.epochID,
                delta: delta,
                tools: materialized.definitions,
                toolTurnLimit: 0,
                reasoningEffort: .disabled,
                contextLength: 32_768
            )

            if holdBeforeProviderTurn {
                await waitForProviderTurnRelease()
            }

            guard let assistant = await consumeModelTurn(
                request: request,
                supportsMultiple: session.supportsMultipleToolCalls
            ) else {
                break loop
            }

            session = (try? store.session(id: sessionID)) ?? session
            session.stepCount += 1
            session.modelMessageCursor = (try? store.messages(sessionID: sessionID).count) ?? session.modelMessageCursor
            try? store.updateSession(session)

            if !assistant.toolCalls.isEmpty {
                if holdBeforeToolSettle {
                    await waitForToolSettleRelease()
                }
                if (try? store.danglingToolCall(sessionID: sessionID)) == nil {
                    break loop
                }
                for call in assistant.toolCalls {
                    if isCancelRequested() { break }
                    let result = await settleCall(call: call, materialized: materialized, session: session)
                    try? store.appendMessage(
                        sessionID: sessionID,
                        message: .toolResult(id: call.id, name: call.name, text: result)
                    )
                }
                session = (try? store.session(id: sessionID)) ?? session
                if await promoteSteerAtBoundary(session: &session) {
                    session = (try? store.session(id: sessionID)) ?? session
                }
                continue loop
            }

            if await promoteQueueAtIdle(session: &session) {
                session = (try? store.session(id: sessionID)) ?? session
                continue loop
            }
            break loop
        }

        if var session = try? store.session(id: sessionID) {
            session.status = .idle
            try? store.updateSession(session)
        }
    }

    private func needsProviderTurn(sessionID: String) -> Bool {
        let messages = (try? store.messages(sessionID: sessionID)) ?? []
        if messages.isEmpty {
            return (try? store.inboxRows(sessionID: sessionID).contains { $0.delivery == .queue }) == true
        }
        guard let last = messages.last else { return false }
        switch last.role {
        case .user:
            return true
        case .tool:
            return true
        case .assistant:
            return !last.toolCalls.isEmpty
        default:
            return false
        }
    }

    private func promoteSteerAtBoundary(session: inout SessionRecord) async -> Bool {
        let inbox = (try? store.inboxRows(sessionID: sessionID)) ?? []
        guard let steer = inbox.first(where: { $0.delivery == .steer }) else { return false }
        try? store.appendMessage(sessionID: sessionID, message: .user(steer.text))
        try? store.deleteInbox(id: steer.id)
        session.stepCount = 1
        try? store.updateSession(session)
        return true
    }

    private func promoteQueueAtIdle(session: inout SessionRecord) async -> Bool {
        let messages = (try? store.messages(sessionID: sessionID)) ?? []
        guard let last = messages.last else { return false }
        guard last.role == .assistant, last.toolCalls.isEmpty else { return false }
        return await promoteOldestQueue(session: &session)
    }

    private func promoteQueueBeforeTurn(session: inout SessionRecord) async -> Bool {
        let messages = (try? store.messages(sessionID: sessionID)) ?? []
        let needsUser = messages.isEmpty || messages.last?.role == .assistant
        guard needsUser else { return true }

        let inbox = (try? store.inboxRows(sessionID: sessionID)) ?? []
        guard inbox.contains(where: { $0.delivery == .queue }) else {
            return !messages.isEmpty
        }

        if messages.isEmpty {
            let hasEpoch = (try? store.epochRecord(
                sessionID: sessionID,
                epochID: session.epochID
            )) != nil
            if !hasEpoch {
                let preview: ContextBoundaryResult
                do {
                    preview = try contextCoordinator.reconcile(
                        store: store,
                        sessionID: sessionID,
                        epochID: session.epochID,
                        projectPath: session.projectPath
                    )
                } catch {
                    return false
                }
                if preview.blocked {
                    return false
                }
            }
        }

        if holdBeforeQueuePromotion {
            await waitForQueuePromotionRelease()
        }

        return await promoteOldestQueue(session: &session)
    }

    private func promoteOldestQueue(session: inout SessionRecord) async -> Bool {
        let inbox = (try? store.inboxRows(sessionID: sessionID)) ?? []
        guard let queued = inbox.first(where: { $0.delivery == .queue }) else { return false }
        try? store.appendMessage(sessionID: sessionID, message: .user(queued.text))
        try? store.deleteInbox(id: queued.id)
        session.stepCount = 0
        try? store.updateSession(session)
        return true
    }

    private func waitForProviderTurnRelease() async {
        await withCheckedContinuation { continuation in
            if !holdBeforeProviderTurn {
                continuation.resume()
                return
            }
            stateLock.withLock { state in
                state.providerTurnWaiters.append(continuation)
            }
        }
    }

    private func waitForToolSettleRelease() async {
        await withCheckedContinuation { continuation in
            if !holdBeforeToolSettle {
                continuation.resume()
                return
            }
            stateLock.withLock { state in
                state.toolSettleWaiters.append(continuation)
            }
        }
    }

    private func waitForQueuePromotionRelease() async {
        await withCheckedContinuation { continuation in
            if !holdBeforeQueuePromotion {
                continuation.resume()
                return
            }
            stateLock.withLock { state in
                state.queuePromotionWaiters.append(continuation)
            }
        }
    }

    private func isCancelRequested() -> Bool {
        stateLock.withLock { $0.cancelRequested }
    }

    private func settle(call: ToolCall, session: SessionRecord) async {
        let agent = agentFor(session)
        let savedAllows = (try? store.permissionRules(projectPath: session.projectPath)) ?? []
        let materialized = ToolRegistry.materialize(
            agent: agent,
            projectPath: session.projectPath,
            savedAllows: savedAllows,
            manualPressed: session.manualPressed,
            onlyNames: materializeOnly
        )
        materializeOnly = nil
        let result = await settleCall(call: call, materialized: materialized, session: session)
        try? store.appendMessage(
            sessionID: sessionID,
            message: .toolResult(id: call.id, name: call.name, text: result)
        )
        if var updated = try? store.session(id: sessionID) {
            _ = await promoteSteerAtBoundary(session: &updated)
        }
    }

    private func settleCall(
        call: ToolCall,
        materialized: MaterializedTools,
        session: SessionRecord
    ) async -> String {
        guard let action = PermissionGate.permissionAction(for: call.name) else {
            return materialized.settle(call: call)
        }

        let resources = PermissionGate.resources(toolName: call.name, arguments: call.arguments)
        let savedAllows = (try? store.permissionRules(projectPath: session.projectPath)) ?? []
        let effects = resources.map { resource in
            PermissionEvaluator.effect(
                agentID: session.agentID,
                action: action,
                resource: resource,
                savedAllows: savedAllows,
                manualPressed: session.manualPressed
            )
        }

        if effects.contains(.deny) {
            return PermissionGate.denialMessage
        }
        if effects.contains(.ask) {
            return await requestPermission(
                action: action,
                resources: resources,
                call: call,
                materialized: materialized,
                session: session
            )
        }

        if materialized.allowedNames.contains(call.name) {
            return materialized.executeAfterApproval(call: call)
        }
        return materialized.settle(call: call)
    }

    private func requestPermission(
        action: String,
        resources: [String],
        call: ToolCall,
        materialized: MaterializedTools,
        session: SessionRecord
    ) async -> String {
        let requestID = UUID().uuidString
        let request = PermissionRequestRecord(
            id: requestID,
            sessionID: sessionID,
            agentID: session.agentID,
            action: action,
            resources: resources,
            toolCallID: call.id,
            toolName: call.name
        )
        try? store.insertPermissionRequest(request)
        try? store.appendHarnessEvent(
            HarnessEventRecord(
                sessionID: sessionID,
                name: "permission.asked",
                permissionRequestID: requestID
            )
        )

        if var waiting = try? store.session(id: sessionID) {
            waiting.status = .waitingPermission
            try? store.updateSession(waiting)
        }

        let reply = await withCheckedContinuation { continuation in
            stateLock.withLock { state in
                state.permissionWaiters[requestID] = continuation
            }
        }

        try? store.appendHarnessEvent(
            HarnessEventRecord(
                sessionID: sessionID,
                name: "permission.replied",
                permissionRequestID: requestID
            )
        )
        try? store.deletePermissionRequest(id: requestID)

        if var running = try? store.session(id: sessionID) {
            running.status = .running
            try? store.updateSession(running)
        }

        switch reply {
        case .once:
            return materialized.executeAfterApproval(call: call)
        case .always:
            for resource in resources {
                try? store.insertPermissionRule(
                    projectPath: session.projectPath,
                    rule: PermissionRule(action: action, resource: resource, effect: .allow)
                )
            }
            return materialized.executeAfterApproval(call: call)
        case .reject:
            return PermissionGate.denialMessage
        }
    }

    private func consumeModelTurn(request: TurnRequest, supportsMultiple: Bool) async -> AssistantTurn? {
        var text = ""
        var reasoning = ""
        var finished: AssistantTurn?
        var assistantStarted = false

        do {
            for try await event in model.complete(request) {
                switch event {
                case .text(let chunk):
                    text += chunk
                    let message = StoredMessage(role: .assistant, text: text, reasoning: reasoning)
                    if assistantStarted {
                        try? store.replaceLastAssistant(sessionID: sessionID, message: message)
                    } else {
                        try? store.appendMessage(sessionID: sessionID, message: message)
                        assistantStarted = true
                    }
                case .reasoning(let chunk):
                    reasoning += chunk
                case .finished(let turn):
                    finished = turn
                }
            }
        } catch {
            return nil
        }

        guard var assistant = finished else { return nil }

        if !supportsMultiple, assistant.toolCalls.count > 1 {
            assistant.toolCalls = [assistant.toolCalls[0]]
        }

        if !assistant.text.isEmpty || !assistant.reasoning.isEmpty {
            assistant.text = text.isEmpty ? assistant.text : text
            assistant.reasoning = reasoning.isEmpty ? assistant.reasoning : reasoning
        }

        if assistantStarted {
            try? store.replaceLastAssistant(sessionID: sessionID, message: .assistant(assistant))
        } else {
            try? store.appendMessage(sessionID: sessionID, message: .assistant(assistant))
        }

        if !assistant.toolCalls.isEmpty, isCancelRequested() {
            _ = try? store.deleteLastAssistantIfBareToolCall(sessionID: sessionID)
            if var session = try? store.session(id: sessionID) {
                session.modelMessageCursor = 0
                try? store.updateSession(session)
                model.reset(epochID: session.epochID)
            }
            return nil
        }

        return assistant
    }

    private func agentFor(_ session: SessionRecord) -> Agent {
        session.agentID == "plan" ? .plan : .build
    }
}
