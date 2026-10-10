import Foundation

enum SubagentRunner {
    static func run(
        parentSessionID: String,
        store: HarnessStore,
        model: any ModelTurn,
        agentID: String,
        prompt: String,
        projectPath: String,
        modelIdentifier: String,
        supportsMultipleToolCalls: Bool,
        manualPressed: Bool,
        contextLength: Int
    ) async -> String {
        let childID = "\(parentSessionID)-sub-\(UUID().uuidString)"
        let epochID = UUID().uuidString
        let childSession = SessionRecord(
            id: childID,
            projectPath: projectPath,
            agentID: agentID,
            modelIdentifier: modelIdentifier,
            epochID: epochID,
            stepCount: 0,
            supportsMultipleToolCalls: supportsMultipleToolCalls,
            status: .idle,
            modelMessageCursor: 0,
            manualPressed: manualPressed,
            contextLength: contextLength
        )
        try? store.insertSession(childSession)
        try? store.setSessionParent(id: childID, parentID: parentSessionID)
        try? store.appendMessage(sessionID: childID, message: .user(prompt))

        let childRunner = SessionRunner(sessionID: childID, store: store, model: model)
        childRunner.contextCoordinator = ContextCoordinator()
        await childRunner.run()

        let messages = (try? store.messages(sessionID: childID)) ?? []
        if let last = messages.last(where: { $0.role == .assistant && $0.toolCalls.isEmpty }) {
            return last.text
        }
        return ""
    }
}
