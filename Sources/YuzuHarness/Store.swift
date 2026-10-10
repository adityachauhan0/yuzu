import Foundation
import GRDB

public struct InboxRow: Sendable, Equatable {
    public var id: Int64
    public var sessionID: String
    public var text: String
    public var delivery: Delivery
}

public struct SessionRecord: Sendable, Equatable {
    public var id: String
    public var projectPath: String
    public var agentID: String
    public var modelIdentifier: String
    public var epochID: String
    public var stepCount: Int
    public var supportsMultipleToolCalls: Bool
    public var status: SessionStatus
    public var modelMessageCursor: Int
    public var manualPressed: Bool = true
    public var contextLength: Int = CompactionSettings.production.contextLength
    public var compactionBufferTokens: Int = CompactionSettings.production.bufferTokens
    public var compactionKeepTokens: Int = CompactionSettings.production.keepTokens
    public var compactionSummary: String?
    public var projectionTailStartOrdinal: Int = 0

    public init(
        id: String,
        projectPath: String,
        agentID: String,
        modelIdentifier: String,
        epochID: String,
        stepCount: Int,
        supportsMultipleToolCalls: Bool,
        status: SessionStatus,
        modelMessageCursor: Int,
        manualPressed: Bool = true,
        contextLength: Int = CompactionSettings.production.contextLength,
        compactionBufferTokens: Int = CompactionSettings.production.bufferTokens,
        compactionKeepTokens: Int = CompactionSettings.production.keepTokens,
        compactionSummary: String? = nil,
        projectionTailStartOrdinal: Int = 0
    ) {
        self.id = id
        self.projectPath = projectPath
        self.agentID = agentID
        self.modelIdentifier = modelIdentifier
        self.epochID = epochID
        self.stepCount = stepCount
        self.supportsMultipleToolCalls = supportsMultipleToolCalls
        self.status = status
        self.modelMessageCursor = modelMessageCursor
        self.manualPressed = manualPressed
        self.contextLength = contextLength
        self.compactionBufferTokens = compactionBufferTokens
        self.compactionKeepTokens = compactionKeepTokens
        self.compactionSummary = compactionSummary
        self.projectionTailStartOrdinal = projectionTailStartOrdinal
    }
}

public final class HarnessStore: Sendable {
    private let dbQueue: DatabaseQueue

    public init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try migrator.migrate(dbQueue)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("slice2") { db in
            try db.create(table: "sessions") { t in
                t.column("id", .text).primaryKey()
                t.column("project_path", .text).notNull()
                t.column("agent_id", .text).notNull()
                t.column("model_identifier", .text).notNull()
                t.column("epoch_id", .text).notNull()
                t.column("step_count", .integer).notNull().defaults(to: 0)
                t.column("supports_multiple_tool_calls", .integer).notNull().defaults(to: 1)
                t.column("status", .text).notNull().defaults(to: SessionStatus.idle.rawValue)
                t.column("model_message_cursor", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "messages") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("session_id", .text).notNull().references("sessions", onDelete: .cascade)
                t.column("ordinal", .integer).notNull()
                t.column("role", .text).notNull()
                t.column("text", .text).notNull().defaults(to: "")
                t.column("reasoning", .text).notNull().defaults(to: "")
                t.column("tool_calls_json", .text).notNull().defaults(to: "[]")
                t.column("tool_call_id", .text)
                t.column("tool_name", .text)
            }
            try db.create(table: "inbox") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("session_id", .text).notNull().references("sessions", onDelete: .cascade)
                t.column("text", .text).notNull()
                t.column("delivery", .text).notNull()
                t.column("created_at", .double).notNull()
            }
            try db.create(index: "messages_session_ordinal", on: "messages", columns: ["session_id", "ordinal"])
        }
        migrator.registerMigration("slice3") { db in
            try db.alter(table: "sessions") { t in
                t.add(column: "manual_pressed", .integer).notNull().defaults(to: 1)
            }
            try db.create(table: "permission_rules") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("project_path", .text).notNull()
                t.column("action", .text).notNull()
                t.column("resource", .text).notNull()
                t.column("effect", .text).notNull()
            }
            try db.create(table: "permission_requests") { t in
                t.column("id", .text).primaryKey()
                t.column("session_id", .text).notNull().references("sessions", onDelete: .cascade)
                t.column("agent_id", .text).notNull()
                t.column("action", .text).notNull()
                t.column("resources_json", .text).notNull()
                t.column("tool_call_id", .text).notNull()
                t.column("tool_name", .text).notNull()
            }
            try db.create(table: "harness_events") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("session_id", .text).notNull().references("sessions", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("permission_request_id", .text)
                t.column("created_at", .double).notNull()
            }
        }
        migrator.registerMigration("slice4") { db in
            try db.create(table: "epochs") { t in
                t.column("session_id", .text).notNull().references("sessions", onDelete: .cascade)
                t.column("epoch_id", .text).notNull()
                t.column("baseline_text", .text).notNull()
                t.column("snapshots_json", .text).notNull().defaults(to: "{}")
                t.primaryKey(["session_id", "epoch_id"])
            }
        }
        migrator.registerMigration("slice8") { db in
            try db.alter(table: "sessions") { t in
                t.add(column: "context_length", .integer).notNull().defaults(to: CompactionSettings.production.contextLength)
                t.add(column: "compaction_buffer_tokens", .integer).notNull()
                    .defaults(to: CompactionSettings.production.bufferTokens)
                t.add(column: "compaction_keep_tokens", .integer).notNull()
                    .defaults(to: CompactionSettings.production.keepTokens)
                t.add(column: "compaction_summary", .text)
                t.add(column: "projection_tail_start_ordinal", .integer).notNull().defaults(to: 0)
            }
            try db.alter(table: "messages") { t in
                t.add(column: "epoch_id", .text)
            }
        }
        migrator.registerMigration("output_tokens") { db in
            try db.alter(table: "messages") { t in
                t.add(column: "output_tokens", .integer)
            }
        }
        migrator.registerMigration("scheduled_tasks") { db in
            try db.create(table: "scheduled_tasks") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("prompt", .text).notNull()
                t.column("schedule_text", .text).notNull()
                t.column("next_run", .double).notNull()
            }
        }
        return migrator
    }

    public func insertSession(_ session: SessionRecord) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO sessions (
                    id, project_path, agent_id, model_identifier, epoch_id,
                    step_count, supports_multiple_tool_calls, status, model_message_cursor,
                    manual_pressed, context_length, compaction_buffer_tokens, compaction_keep_tokens,
                    compaction_summary, projection_tail_start_ordinal
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    session.id,
                    session.projectPath,
                    session.agentID,
                    session.modelIdentifier,
                    session.epochID,
                    session.stepCount,
                    session.supportsMultipleToolCalls ? 1 : 0,
                    session.status.rawValue,
                    session.modelMessageCursor,
                    session.manualPressed ? 1 : 0,
                    session.contextLength,
                    session.compactionBufferTokens,
                    session.compactionKeepTokens,
                    session.compactionSummary,
                    session.projectionTailStartOrdinal,
                ]
            )
        }
    }

    public func session(id: String) throws -> SessionRecord? {
        try dbQueue.read { db in
            try SessionRecord.fetchOne(db, sql: "SELECT * FROM sessions WHERE id = ?", arguments: [id])
        }
    }

    public func updateSession(_ session: SessionRecord) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE sessions SET
                    project_path = ?, agent_id = ?, model_identifier = ?, epoch_id = ?,
                    step_count = ?, supports_multiple_tool_calls = ?, status = ?, model_message_cursor = ?,
                    manual_pressed = ?, context_length = ?, compaction_buffer_tokens = ?,
                    compaction_keep_tokens = ?, compaction_summary = ?, projection_tail_start_ordinal = ?
                WHERE id = ?
                """,
                arguments: [
                    session.projectPath,
                    session.agentID,
                    session.modelIdentifier,
                    session.epochID,
                    session.stepCount,
                    session.supportsMultipleToolCalls ? 1 : 0,
                    session.status.rawValue,
                    session.modelMessageCursor,
                    session.manualPressed ? 1 : 0,
                    session.contextLength,
                    session.compactionBufferTokens,
                    session.compactionKeepTokens,
                    session.compactionSummary,
                    session.projectionTailStartOrdinal,
                    session.id,
                ]
            )
        }
    }

    public func appendInbox(sessionID: String, text: String, delivery: Delivery) throws -> Int64 {
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO inbox (session_id, text, delivery, created_at) VALUES (?, ?, ?, ?)",
                arguments: [sessionID, text, delivery.rawValue, Date().timeIntervalSince1970]
            )
            return db.lastInsertedRowID
        }
    }

    public func inboxRows(sessionID: String) throws -> [InboxRow] {
        try dbQueue.read { db in
            try InboxRow.fetchAll(
                db,
                sql: "SELECT id, session_id, text, delivery FROM inbox WHERE session_id = ? ORDER BY id ASC",
                arguments: [sessionID]
            )
        }
    }

    public func deleteInbox(id: Int64) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM inbox WHERE id = ?", arguments: [id])
        }
    }

    public func messageEpochIDs(sessionID: String) throws -> [String] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT epoch_id FROM messages WHERE session_id = ? ORDER BY ordinal ASC",
                arguments: [sessionID]
            )
            return rows.map { row in
                let value: String? = row["epoch_id"]
                return value ?? ""
            }
        }
    }

    public func toolMessagesContaining(text: String, sessionIDPrefix: String) throws -> [StoredMessage] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT role, text, reasoning, tool_calls_json, tool_call_id, tool_name
                FROM messages
                WHERE session_id LIKE ? AND role = 'tool' AND text LIKE ?
                ORDER BY ordinal ASC
                """,
                arguments: ["\(sessionIDPrefix)%", "%\(text)%"]
            )
            return rows.map { row in
                let toolCallsJSON: String = row["tool_calls_json"]
                let toolCalls = (try? JSONDecoder().decode([ToolCall].self, from: Data(toolCallsJSON.utf8))) ?? []
                return StoredMessage(
                    role: .tool,
                    text: row["text"],
                    reasoning: row["reasoning"],
                    toolCalls: toolCalls,
                    toolCallID: row["tool_call_id"],
                    toolName: row["tool_name"]
                )
            }
        }
    }

    public func messages(sessionID: String) throws -> [StoredMessage] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT role, text, reasoning, tool_calls_json, tool_call_id, tool_name, output_tokens
                FROM messages WHERE session_id = ? ORDER BY ordinal ASC
                """,
                arguments: [sessionID]
            )
            return rows.map { row in
                let toolCallsJSON: String = row["tool_calls_json"]
                let toolCalls = (try? JSONDecoder().decode([ToolCall].self, from: Data(toolCallsJSON.utf8))) ?? []
                return StoredMessage(
                    role: StoredMessage.Role(rawValue: row["role"]) ?? .user,
                    text: row["text"],
                    reasoning: row["reasoning"],
                    toolCalls: toolCalls,
                    toolCallID: row["tool_call_id"],
                    toolName: row["tool_name"],
                    outputTokens: row["output_tokens"]
                )
            }
        }
    }

    public func userMessages(sessionID: String) throws -> [StoredMessage] {
        try messages(sessionID: sessionID).filter { $0.role == .user }
    }

    public func deleteMessages(sessionID: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM messages WHERE session_id = ?", arguments: [sessionID])
        }
    }

    public func appendMessage(sessionID: String, message: StoredMessage, epochID: String? = nil) throws {
        try dbQueue.write { db in
            let ordinal = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(ordinal), -1) + 1 FROM messages WHERE session_id = ?",
                arguments: [sessionID]
            ) ?? 0
            let toolCallsData = try JSONEncoder().encode(message.toolCalls)
            let toolCallsJSON = String(decoding: toolCallsData, as: UTF8.self)
            let resolvedEpoch: String
            if let epochID {
                resolvedEpoch = epochID
            } else if let session = try SessionRecord.fetchOne(
                db,
                sql: "SELECT * FROM sessions WHERE id = ?",
                arguments: [sessionID]
            ) {
                resolvedEpoch = session.epochID
            } else {
                resolvedEpoch = ""
            }
            try db.execute(
                sql: """
                INSERT INTO messages (
                    session_id, ordinal, role, text, reasoning, tool_calls_json, tool_call_id, tool_name,
                    epoch_id, output_tokens
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    sessionID,
                    ordinal,
                    message.role.rawValue,
                    message.text,
                    message.reasoning,
                    toolCallsJSON,
                    message.toolCallID,
                    message.toolName,
                    resolvedEpoch,
                    message.outputTokens,
                ]
            )
        }
    }

    public func replaceLastAssistant(sessionID: String, message: StoredMessage) throws {
        try dbQueue.write { db in
            guard let rowID = try Int64.fetchOne(
                db,
                sql: """
                SELECT id FROM messages
                WHERE session_id = ? AND role = 'assistant'
                ORDER BY ordinal DESC LIMIT 1
                """,
                arguments: [sessionID]
            ) else {
                try appendMessage(sessionID: sessionID, message: message)
                return
            }
            let toolCallsData = try JSONEncoder().encode(message.toolCalls)
            let toolCallsJSON = String(decoding: toolCallsData, as: UTF8.self)
            try db.execute(
                sql: """
                UPDATE messages SET text = ?, reasoning = ?, tool_calls_json = ?, output_tokens = ?
                WHERE id = ?
                """,
                arguments: [message.text, message.reasoning, toolCallsJSON, message.outputTokens, rowID]
            )
        }
    }

    public func deleteLastAssistantIfBareToolCall(sessionID: String) throws -> Bool {
        try dbQueue.write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT id, tool_calls_json FROM messages
                WHERE session_id = ? AND role = 'assistant'
                ORDER BY ordinal DESC LIMIT 1
                """,
                arguments: [sessionID]
            ) else {
                return false
            }
            let toolCallsJSON: String = row["tool_calls_json"]
            let toolCalls = (try? JSONDecoder().decode([ToolCall].self, from: Data(toolCallsJSON.utf8))) ?? []
            guard !toolCalls.isEmpty else { return false }
            let assistantOrdinal = try Int.fetchOne(
                db,
                sql: "SELECT ordinal FROM messages WHERE id = ?",
                arguments: [row["id"]]
            ) ?? 0
            let hasResults = try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*) FROM messages
                WHERE session_id = ? AND role = 'tool' AND ordinal > ?
                """,
                arguments: [sessionID, assistantOrdinal]
            ) ?? 0
            guard hasResults == 0 else { return false }
            try db.execute(sql: "DELETE FROM messages WHERE id = ?", arguments: [row["id"]])
            return true
        }
    }

    public func danglingToolCall(sessionID: String) throws -> ToolCall? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT id, ordinal, tool_calls_json FROM messages
                WHERE session_id = ? AND role = 'assistant'
                ORDER BY ordinal DESC LIMIT 1
                """,
                arguments: [sessionID]
            ) else {
                return nil
            }
            let toolCallsJSON: String = row["tool_calls_json"]
            let toolCalls = (try? JSONDecoder().decode([ToolCall].self, from: Data(toolCallsJSON.utf8))) ?? []
            guard let call = toolCalls.first else { return nil }
            let assistantOrdinal: Int = row["ordinal"]
            let resultCount = try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*) FROM messages
                WHERE session_id = ? AND role = 'tool' AND tool_call_id = ?
                """,
                arguments: [sessionID, call.id]
            ) ?? 0
            if resultCount > 0 {
                return nil
            }
            return call
        }
    }

    public func insertAssistantWithDanglingCall(sessionID: String, call: ToolCall) throws {
        try appendMessage(
            sessionID: sessionID,
            message: StoredMessage(
                role: .assistant,
                text: "",
                toolCalls: [call]
            )
        )
    }

    public func permissionRules(projectPath: String) throws -> [PermissionRule] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT action, resource, effect FROM permission_rules
                WHERE project_path = ? ORDER BY id ASC
                """,
                arguments: [projectPath]
            )
            return rows.map { row in
                PermissionRule(
                    action: row["action"],
                    resource: row["resource"],
                    effect: PermissionEffect(rawValue: row["effect"]) ?? .allow
                )
            }
        }
    }

    public func insertPermissionRule(projectPath: String, rule: PermissionRule) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO permission_rules (project_path, action, resource, effect)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [projectPath, rule.action, rule.resource, rule.effect.rawValue]
            )
        }
    }

    public func insertPermissionRequest(_ request: PermissionRequestRecord) throws {
        let resourcesData = try JSONEncoder().encode(request.resources)
        let resourcesJSON = String(decoding: resourcesData, as: UTF8.self)
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO permission_requests (
                    id, session_id, agent_id, action, resources_json, tool_call_id, tool_name
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    request.id,
                    request.sessionID,
                    request.agentID,
                    request.action,
                    resourcesJSON,
                    request.toolCallID,
                    request.toolName,
                ]
            )
        }
    }

    public func deletePermissionRequest(id: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM permission_requests WHERE id = ?", arguments: [id])
        }
    }

    public func pendingPermissionRequests(sessionID: String) throws -> [PermissionRequestRecord] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, session_id, agent_id, action, resources_json, tool_call_id, tool_name
                FROM permission_requests WHERE session_id = ?
                """,
                arguments: [sessionID]
            )
            return rows.map { row in
                let resourcesJSON: String = row["resources_json"]
                let resources = (try? JSONDecoder().decode([String].self, from: Data(resourcesJSON.utf8))) ?? []
                return PermissionRequestRecord(
                    id: row["id"],
                    sessionID: row["session_id"],
                    agentID: row["agent_id"],
                    action: row["action"],
                    resources: resources,
                    toolCallID: row["tool_call_id"],
                    toolName: row["tool_name"]
                )
            }
        }
    }

    public func appendHarnessEvent(_ event: HarnessEventRecord) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO harness_events (session_id, name, permission_request_id, created_at)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [
                    event.sessionID,
                    event.name,
                    event.permissionRequestID,
                    Date().timeIntervalSince1970,
                ]
            )
        }
    }

    public func insertEpoch(_ record: EpochRecord) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO epochs (session_id, epoch_id, baseline_text, snapshots_json)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [
                    record.sessionID,
                    record.epochID,
                    record.baselineText,
                    record.snapshotsJSON,
                ]
            )
        }
    }

    public func epochRecord(sessionID: String, epochID: String) throws -> EpochRecord? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT session_id, epoch_id, baseline_text, snapshots_json
                FROM epochs WHERE session_id = ? AND epoch_id = ?
                """,
                arguments: [sessionID, epochID]
            ) else {
                return nil
            }
            return EpochRecord(
                sessionID: row["session_id"],
                epochID: row["epoch_id"],
                baselineText: row["baseline_text"],
                snapshotsJSON: row["snapshots_json"]
            )
        }
    }

    public func updateEpochSnapshots(sessionID: String, epochID: String, snapshotsJSON: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE epochs SET snapshots_json = ?
                WHERE session_id = ? AND epoch_id = ?
                """,
                arguments: [snapshotsJSON, sessionID, epochID]
            )
        }
    }

    public func harnessEvents(sessionID: String) throws -> [HarnessEventRecord] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT session_id, name, permission_request_id
                FROM harness_events WHERE session_id = ? ORDER BY id ASC
                """,
                arguments: [sessionID]
            )
            return rows.map { row in
                HarnessEventRecord(
                    sessionID: row["session_id"],
                    name: row["name"],
                    permissionRequestID: row["permission_request_id"]
                )
            }
        }
    }

    public func scheduledTasks() throws -> [ScheduledTaskRecord] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM scheduled_tasks ORDER BY next_run ASC")
            return rows.map { row in
                ScheduledTaskRecord(
                    id: row["id"],
                    name: row["name"],
                    prompt: row["prompt"],
                    scheduleText: row["schedule_text"],
                    nextRun: Date(timeIntervalSince1970: row["next_run"])
                )
            }
        }
    }

    public func allSessions() throws -> [SessionRecord] {
        try dbQueue.read { db in
            try SessionRecord.fetchAll(db, sql: "SELECT * FROM sessions ORDER BY id ASC")
        }
    }

    public func exportSessionDocuments() throws -> [SessionDocument] {
        try allSessions().map { session in
            SessionDocument(
                id: session.id,
                projectPath: session.projectPath,
                modelIdentifier: session.modelIdentifier,
                messages: try messages(sessionID: session.id)
            )
        }
    }

    public func importSessionDocuments(_ documents: [SessionDocument]) throws {
        for document in documents {
            var id = document.id
            if try session(id: id) != nil {
                id = "\(document.id)-\(UUID().uuidString)"
            }
            try insertSession(
                SessionRecord(
                    id: id,
                    projectPath: document.projectPath,
                    agentID: "build",
                    modelIdentifier: document.modelIdentifier,
                    epochID: "epoch-import",
                    stepCount: 0,
                    supportsMultipleToolCalls: true,
                    status: .idle,
                    modelMessageCursor: 0
                )
            )
            for message in document.messages {
                try appendMessage(sessionID: id, message: message, epochID: "epoch-import")
            }
        }
    }

    public func insertScheduledTask(_ task: ScheduledTaskRecord) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO scheduled_tasks (id, name, prompt, schedule_text, next_run)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [
                    task.id,
                    task.name,
                    task.prompt,
                    task.scheduleText,
                    task.nextRun.timeIntervalSince1970,
                ]
            )
        }
    }

    public func updateScheduledTaskNextRun(id: String, nextRun: Date) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE scheduled_tasks SET next_run = ? WHERE id = ?",
                arguments: [nextRun.timeIntervalSince1970, id]
            )
        }
    }
}

extension SessionRecord: FetchableRecord {
    public init(row: Row) {
        id = row["id"]
        projectPath = row["project_path"]
        agentID = row["agent_id"]
        modelIdentifier = row["model_identifier"]
        epochID = row["epoch_id"]
        stepCount = row["step_count"]
        supportsMultipleToolCalls = (row["supports_multiple_tool_calls"] as Int) != 0
        status = SessionStatus(rawValue: row["status"]) ?? .idle
        modelMessageCursor = row["model_message_cursor"]
        if let manual: Int = row["manual_pressed"] {
            manualPressed = manual != 0
        } else {
            manualPressed = true
        }
        contextLength = row["context_length"] ?? CompactionSettings.production.contextLength
        compactionBufferTokens = row["compaction_buffer_tokens"] ?? CompactionSettings.production.bufferTokens
        compactionKeepTokens = row["compaction_keep_tokens"] ?? CompactionSettings.production.keepTokens
        compactionSummary = row["compaction_summary"]
        projectionTailStartOrdinal = row["projection_tail_start_ordinal"] ?? 0
    }
}

extension InboxRow: FetchableRecord {
    public init(row: Row) {
        id = row["id"]
        sessionID = row["session_id"]
        text = row["text"]
        delivery = Delivery(rawValue: row["delivery"]) ?? .queue
    }
}
