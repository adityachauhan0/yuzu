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
                    projectPath: session.projectPath,
                    agentID: session.agentID
                )
            } catch {
                break loop
            }
            if contextResult.blocked {
                break loop
            }

            if await runCompactionIfNeeded(session: &session) {
                session = (try? store.session(id: sessionID)) ?? session
                continue loop
            }

            let agent = agentFor(session)
            if let stepLimit = agent.steps, session.stepCount >= stepLimit {
                break loop
            }
            let savedAllows = (try? store.permissionRules(projectPath: session.projectPath)) ?? []
            let materialized = ToolRegistry.materialize(
                agent: agent,
                projectPath: session.projectPath,
                sessionID: sessionID,
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
                contextLength: session.contextLength
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
                        projectPath: session.projectPath,
                        agentID: session.agentID
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
            sessionID: sessionID,
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
        guard let action = PermissionGate.permissionAction(for: call.name, arguments: call.arguments) else {
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
            return await executeApproved(call: call, materialized: materialized)
        }
        return materialized.settle(call: call)
    }

    public func mcpConnect(_ config: MCPServerConfig) async throws {
        guard let session = try? store.session(id: sessionID) else { return }
        try await MCPHub.shared.connect(config: config, projectPath: session.projectPath)
    }

    public func mcpDisconnect(_ serverName: String) {
        MCPHub.shared.disconnect(serverName: serverName)
    }

    public func invokeMCPPrompt(serverName: String, name: String) async throws {
        let text = try await MCPHub.shared.getPromptText(serverName: serverName, name: name)
        try store.appendMessage(sessionID: sessionID, message: .user(text))
        await run()
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
            return await executeApproved(call: call, materialized: materialized)
        case .always:
            for resource in resources {
                try? store.insertPermissionRule(
                    projectPath: session.projectPath,
                    rule: PermissionRule(action: action, resource: resource, effect: .allow)
                )
            }
            return await executeApproved(call: call, materialized: materialized)
        case .reject:
            return PermissionGate.denialMessage
        }
    }

    private func executeApproved(call: ToolCall, materialized: MaterializedTools) async -> String {
        if call.name == "read_resource" {
            guard let uri = stringField(call.arguments, key: "uri") else {
                return "Error: missing uri"
            }
            let text = await MCPHub.shared.readResource(uri: uri)
            return ToolOutput.project(raw: text, sessionID: materialized.sessionID, callID: call.id)
        }
        if call.name == "task" {
            return await executeTask(call: call, materialized: materialized)
        }
        if materialized.isMCPTool(call.name) {
            let text = await MCPHub.shared.execute(harnessName: call.name, arguments: call.arguments)
            return ToolOutput.project(raw: text, sessionID: materialized.sessionID, callID: call.id)
        }
        return materialized.executeAfterApproval(call: call)
    }

    private func executeTask(call: ToolCall, materialized: MaterializedTools) async -> String {
        guard let agentID = stringField(call.arguments, key: "agent"),
              let prompt = stringField(call.arguments, key: "prompt") else {
            return "Error: missing agent or prompt"
        }
        guard let childAgent = AgentCatalog.agent(id: agentID), childAgent.allowsSubagent else {
            return "Error: agent cannot run as subagent"
        }
        guard let session = try? store.session(id: sessionID) else {
            return "Error: session missing"
        }
        let result = await SubagentRunner.run(
            parentSessionID: sessionID,
            store: store,
            model: model,
            agentID: agentID,
            prompt: prompt,
            projectPath: session.projectPath,
            modelIdentifier: session.modelIdentifier,
            supportsMultipleToolCalls: session.supportsMultipleToolCalls,
            manualPressed: session.manualPressed,
            contextLength: session.contextLength
        )
        return ToolOutput.project(raw: result, sessionID: materialized.sessionID, callID: call.id)
    }

    private func consumeModelTurn(request: TurnRequest, supportsMultiple: Bool) async -> AssistantTurn? {
        var text = ""
        var reasoning = ""
        var finished: AssistantTurn?
        var assistantStarted = false

        do {
            try await ModelTurnCoordinator.shared.withTurn {
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

    private func runCompactionIfNeeded(session: inout SessionRecord) async -> Bool {
        let settings = CompactionSettings(session: session)
        let baseline = try? contextCoordinator.baselineSystemText(
            store: store,
            sessionID: sessionID,
            epochID: session.epochID
        )
        let projected = (try? contextCoordinator.projectedHistory(
            store: store,
            sessionID: sessionID,
            session: session
        )) ?? []
        guard Compaction.needsCompaction(projected: projected, baseline: baseline, settings: settings) else {
            return false
        }

        let allMessages = (try? store.messages(sessionID: sessionID)) ?? []
        let selection = Compaction.selectMessages(messages: allMessages, settings: settings)
        guard !selection.head.isEmpty else { return false }

        let prompt = Compaction.buildSummaryPrompt(
            head: selection.head,
            previousSummary: session.compactionSummary
        )
        let summaryRequest = TurnRequest(
            epochID: session.epochID,
            delta: [.user(prompt)],
            tools: [],
            toolTurnLimit: 0,
            reasoningEffort: .disabled,
            contextLength: session.contextLength
        )

        guard let summaryText = await consumeCompactionSummary(request: summaryRequest) else {
            return false
        }

        let newEpochID = UUID().uuidString
        session.epochID = newEpochID
        session.compactionSummary = summaryText
        session.projectionTailStartOrdinal = selection.tailStartOrdinal
        session.modelMessageCursor = 0
        try? store.updateSession(session)

        _ = try? contextCoordinator.reconcile(
            store: store,
            sessionID: sessionID,
            epochID: newEpochID,
            projectPath: session.projectPath,
            agentID: session.agentID
        )

        model.reset(epochID: newEpochID)
        return true
    }

    private func consumeCompactionSummary(request: TurnRequest) async -> String? {
        var text = ""
        var finished: AssistantTurn?
        do {
            try await ModelTurnCoordinator.shared.withTurn {
                for try await event in model.complete(request) {
                    switch event {
                    case .text(let chunk):
                        text += chunk
                    case .reasoning:
                        break
                    case .finished(let turn):
                        finished = turn
                    }
                }
            }
        } catch {
            return nil
        }
        guard finished != nil else { return nil }
        let summary = text.isEmpty ? (finished?.text ?? "") : text
        return summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : summary
    }

    private func agentFor(_ session: SessionRecord) -> Agent {
        AgentCatalog.agent(id: session.agentID) ?? .build
    }
}
