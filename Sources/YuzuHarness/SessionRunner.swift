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
        var earlyPermissionReplies: [String: PermissionReply] = [:]
    }

    public let sessionID: String
    /// Where `mcp` reads and writes servers. The app points this at its support directory.
    public var mcpConfigURL: URL = MCPTool.defaultFileURL()
    private let store: HarnessStore
    private let modelBox: OSAllocatedUnfairLock<any ModelTurn>

    /// Module-qualified type of the installed turn. Display names are not accepted as a substitute.
    public var installedModelTypeName: String {
        String(reflecting: type(of: activeModel()))
    }

    public var modelBacking: ModelBacking {
        activeModel().backing
    }

    /// Swaps the engine behind an already-open window. Weights stay in uzu's cache, not in the app bundle.
    public func useModel(_ next: any ModelTurn) {
        modelBox.withLock { $0 = next }
    }

    private func activeModel() -> any ModelTurn {
        modelBox.withLock { $0 }
    }
    private let stateLock = OSAllocatedUnfairLock(initialState: RunnerState())

    /// Test hook: block the drain before queue promotion (L1).
    public var holdBeforeQueuePromotion = false
    /// Test hook: block after a model turn returns tool calls, before settlement (L7).
    public var holdBeforeToolSettle = false
    /// Test hook: block immediately before calling the model (L9).
    public var holdBeforeProviderTurn = false
    private let liveGenerationLock = OSAllocatedUnfairLock<LiveGeneration?>(initialState: nil)

    /// Token totals for the turn that is running, or the one that just finished.
    public func liveGeneration() -> LiveGeneration? {
        liveGenerationLock.withLock { $0 }
    }

    /// The effort the window selected. Tests leave this `.disabled`.
    public var requestedReasoningEffort: ReasoningEffort = .disabled

    /// Overrides materialized tool names for the next boundary (tests).
    public var materializeOnly: Set<String>?

    public var contextCoordinator = ContextCoordinator()

    public init(sessionID: String, store: HarnessStore, model: any ModelTurn) {
        self.sessionID = sessionID
        self.store = store
        self.modelBox = OSAllocatedUnfairLock(initialState: model)
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
        let status = try? store.session(id: sessionID)?.status
        let inFlight = status == .running || status == .waitingPermission
        stateLock.withLock { $0.cancelRequested = true }

        if (try? store.deleteLastAssistantIfBareToolCall(sessionID: sessionID)) == true {
            if var session = try? store.session(id: sessionID) {
                session.modelMessageCursor = 0
                try? store.updateSession(session)
                activeModel().reset(epochID: session.epochID)
            }
        }

        let waiters = stateLock.withLock { state -> [CheckedContinuation<PermissionReply, Never>] in
            let values = Array(state.permissionWaiters.values)
            state.permissionWaiters.removeAll()
            return values
        }
        for waiter in waiters {
            waiter.resume(returning: .reject)
        }

        if !inFlight {
            stateLock.withLock { $0.cancelRequested = false }
        }
    }

    public func replyPermission(_ id: String, _ reply: PermissionReply) async {
        let waiter = stateLock.withLock { state -> CheckedContinuation<PermissionReply, Never>? in
            if let waiter = state.permissionWaiters.removeValue(forKey: id) {
                return waiter
            }
            state.earlyPermissionReplies[id] = reply
            return nil
        }
        waiter?.resume(returning: reply)
    }

    public func setManualPressed(_ pressed: Bool) async {
        await setPermissionPosture(PermissionPosture(manualPressed: pressed))
    }

    public func setPermissionPosture(_ posture: PermissionPosture) async {
        if var session = try? store.session(id: sessionID) {
            session.permissionPosture = posture
            try? store.updateSession(session)
        }
    }

    public func setAgent(_ id: String) async {
        if var session = try? store.session(id: sessionID) {
            session.agentID = id
            try? store.updateSession(session)
        }
    }

    public func revertLastUserTurn() async -> Bool {
        guard (try? store.revertLastUserTurn(sessionID: sessionID)) == true else { return false }
        if var session = try? store.session(id: sessionID) {
            session.modelMessageCursor = (try? store.messages(sessionID: sessionID).count) ?? session.modelMessageCursor
            try? store.updateSession(session)
            activeModel().reset(epochID: session.epochID)
        }
        return true
    }

    public func admitSteerDuringSettle(_ text: String) throws {
        _ = try store.appendInbox(sessionID: sessionID, text: text, delivery: .steer)
    }

    private func drainLoop() async {
        guard var session = try? store.session(id: sessionID) else { return }
        session.status = .running
        try? store.updateSession(session)
        defer {
            stateLock.withLock { $0.cancelRequested = false }
        }

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
                stateLock.withLock { $0.cancelRequested = false }
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
                posture: session.permissionPosture,
                onlyNames: materializeOnly
            )
            materializeOnly = nil

            session = (try? store.session(id: sessionID)) ?? session
            let model = activeModel()
            if session.modelMessageCursor > 0, ModelEpochLedger.shared.lastEpoch(of: model) != session.epochID {
                session.modelMessageCursor = 0
                try? store.updateSession(session)
            }
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
                reasoningEffort: requestedReasoningEffort,
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
            ModelEpochLedger.shared.record(session.epochID, for: model)

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
                    if call.name == "bash" {
                        try? store.upsertToolResult(
                            sessionID: sessionID,
                            callID: call.id,
                            name: call.name,
                            text: result
                        )
                    } else {
                        try? store.appendMessage(
                            sessionID: sessionID,
                            message: .toolResult(id: call.id, name: call.name, text: result)
                        )
                    }
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
            posture: session.permissionPosture,
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
        if call.name == QuestionTool.definition.name, materialized.allowedNames.contains(call.name) {
            guard let question = QuestionTool.questionText(from: call.arguments) else {
                return "Error: missing question"
            }
            return await QuestionTool.Broker.shared.register(
                sessionID: sessionID,
                callID: call.id,
                question: question
            )
        }
        if call.name == TodoTool.definition.name, materialized.allowedNames.contains(call.name) {
            guard let items = TodoTool.parse(call.arguments) else {
                return "todowrite needs todos: a list of {content, status}."
            }
            try? store.replaceTodos(sessionID: sessionID, items)
            return TodoTool.summary(items)
        }
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
                manualPressed: session.manualPressed,
                posture: session.permissionPosture
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
            return await executeApproved(call: call, materialized: materialized, session: session)
        }
        return materialized.settle(call: call)
    }

    private func executeMCP(call: ToolCall, session: SessionRecord) async -> String {
        let action = (stringField(call.arguments, key: "action") ?? "list").lowercased()
        switch action {
        case "list":
            let entries = MCPTool.read(mcpConfigURL)
            if entries.isEmpty { return "No MCP servers installed." }
            return entries.map { "\($0.name) enabled=\($0.enabled)" }.joined(separator: "\n")
        case "remove":
            guard let name = stringField(call.arguments, key: "name"), !name.isEmpty else {
                return "Error: missing name"
            }
            do {
                _ = try MCPTool.remove(name: name, at: mcpConfigURL)
            } catch {
                return "Error: \(error)"
            }
            MCPHub.shared.disconnect(serverName: name)
            return "Removed MCP server \(name)."
        case "install":
            let requested = stringField(call.arguments, key: "name") ?? ""
            let name = requested.isEmpty ? "duckduckgo" : requested
            do {
                let config = try MCPTool.config(
                    name: name,
                    command: stringField(call.arguments, key: "command"),
                    args: MCPTool.stringArgs(call.arguments),
                    url: stringField(call.arguments, key: "url")
                )
                _ = try MCPTool.install(
                    name: name,
                    command: stringField(call.arguments, key: "command"),
                    args: MCPTool.stringArgs(call.arguments),
                    url: stringField(call.arguments, key: "url"),
                    at: mcpConfigURL
                )
                do {
                    try await MCPHub.shared.connect(config: config, projectPath: session.projectPath)
                    return "Installed MCP server \(name) and connected it. Its tools are available on the next turn."
                } catch {
                    return "Installed MCP server \(name). Connection failed: \(error). The entry is saved and can be connected again."
                }
            } catch {
                return "Error: \(error)"
            }
        default:
            return "Error: action must be install, list, or remove"
        }
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
            let early = stateLock.withLock { state -> PermissionReply? in
                if let reply = state.earlyPermissionReplies.removeValue(forKey: requestID) {
                    return reply
                }
                state.permissionWaiters[requestID] = continuation
                return nil
            }
            if let early {
                continuation.resume(returning: early)
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
            return await executeApproved(call: call, materialized: materialized, session: session)
        case .always:
            for resource in resources {
                try? store.insertPermissionRule(
                    projectPath: session.projectPath,
                    rule: PermissionRule(action: action, resource: resource, effect: .allow)
                )
            }
            return await executeApproved(call: call, materialized: materialized, session: session)
        case .reject:
            return PermissionGate.denialMessage
        }
    }

    private func executeApproved(
        call: ToolCall,
        materialized: MaterializedTools,
        session: SessionRecord
    ) async -> String {
        if call.name == "bash" {
            return await executeBashStreaming(call: call, materialized: materialized, session: session)
        }
        if call.name == MCPTool.definition.name {
            return await executeMCP(call: call, session: session)
        }
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

    private func executeBashStreaming(
        call: ToolCall,
        materialized: MaterializedTools,
        session: SessionRecord
    ) async -> String {
        guard let command = stringField(call.arguments, key: "command") else {
            return "Error: missing command"
        }
        let timeout = {
            guard case .object(let object) = call.arguments else { return nil as Double? }
            switch object["timeout"] {
            case .number(let value): return value
            case .string(let text): return Double(text)
            default: return nil
            }
        }()
        let root = ProjectPaths.projectRootURL(path: session.projectPath).path
        let accumulated = OSAllocatedUnfairLock(initialState: "Ran: \(command)\n")
        try? store.upsertToolResult(
            sessionID: sessionID,
            callID: call.id,
            name: call.name,
            text: accumulated.withLock { $0 }
        )
        let body = BashRunner.run(
            command: command,
            workingDirectory: root,
            timeoutSeconds: timeout
        ) { chunk in
            let text = accumulated.withLock { state -> String in
                state += chunk
                return state
            }
            try? self.store.updateToolResultText(
                sessionID: self.sessionID,
                toolCallID: call.id,
                text: text
            )
        }
        return ToolOutput.project(raw: body, sessionID: materialized.sessionID, callID: call.id)
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
            parentToolCallID: call.id,
            store: store,
            model: activeModel(),
            agentID: agentID,
            prompt: prompt,
            projectPath: session.projectPath,
            modelIdentifier: session.modelIdentifier,
            supportsMultipleToolCalls: session.supportsMultipleToolCalls,
            manualPressed: session.manualPressed,
            permissionPosture: session.permissionPosture,
            contextLength: session.contextLength
        )
        return ToolOutput.project(raw: result, sessionID: materialized.sessionID, callID: call.id)
    }

    private func consumeModelTurn(request: TurnRequest, supportsMultiple: Bool) async -> AssistantTurn? {
        var text = ""
        var reasoning = ""
        var finished: AssistantTurn?
        var assistantStarted = false
        liveGenerationLock.withLock { $0 = nil }

        do {
            try await ModelTurnCoordinator.shared.withTurn {
                let turn = activeModel()
                for try await event in turn.complete(request) {
                    // Leaving the stream cancels the turn, which stops the engine mid-generation.
                    if isCancelRequested() { break }
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
                        let message = StoredMessage(role: .assistant, text: text, reasoning: reasoning)
                        if assistantStarted {
                            try? store.replaceLastAssistant(sessionID: sessionID, message: message)
                        } else {
                            try? store.appendMessage(sessionID: sessionID, message: message)
                            assistantStarted = true
                        }
                    case .usage(let input, let cached, let output, let duration):
                        liveGenerationLock.withLock {
                            $0 = LiveGeneration(
                                inputTokens: input,
                                cachedTokens: cached,
                                outputTokens: output,
                                duration: duration
                            )
                        }
                    case .finished(let turn):
                        finished = turn
                    }
                }
            }
        } catch {
            print("Yuzu model turn failed: \(error)")
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
            if (try? store.deleteLastAssistantIfBareToolCall(sessionID: sessionID)) == true {
                if var session = try? store.session(id: sessionID) {
                    session.modelMessageCursor = 0
                    try? store.updateSession(session)
                    activeModel().reset(epochID: session.epochID)
                }
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

        activeModel().reset(epochID: newEpochID)
        try? store.appendMessage(
            sessionID: sessionID,
            message: .system("Earlier context was summarized."),
            epochID: newEpochID
        )
        try? store.appendHarnessEvent(
            HarnessEventRecord(sessionID: sessionID, name: "compaction.applied", permissionRequestID: nil)
        )
        return true
    }

    private func consumeCompactionSummary(request: TurnRequest) async -> String? {
        var text = ""
        var finished: AssistantTurn?
        do {
            try await ModelTurnCoordinator.shared.withTurn {
                let turn = activeModel()
                for try await event in turn.complete(request) {
                    switch event {
                    case .text(let chunk):
                        text += chunk
                    case .reasoning, .usage:
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
