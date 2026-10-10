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
        return migrator
    }

    public func insertSession(_ session: SessionRecord) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO sessions (
                    id, project_path, agent_id, model_identifier, epoch_id,
                    step_count, supports_multiple_tool_calls, status, model_message_cursor
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                    step_count = ?, supports_multiple_tool_calls = ?, status = ?, model_message_cursor = ?
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

    public func messages(sessionID: String) throws -> [StoredMessage] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT role, text, reasoning, tool_calls_json, tool_call_id, tool_name
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
                    toolName: row["tool_name"]
                )
            }
        }
    }

    public func userMessages(sessionID: String) throws -> [StoredMessage] {
        try messages(sessionID: sessionID).filter { $0.role == .user }
    }

    public func appendMessage(sessionID: String, message: StoredMessage) throws {
        try dbQueue.write { db in
            let ordinal = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(ordinal), -1) + 1 FROM messages WHERE session_id = ?",
                arguments: [sessionID]
            ) ?? 0
            let toolCallsData = try JSONEncoder().encode(message.toolCalls)
            let toolCallsJSON = String(decoding: toolCallsData, as: UTF8.self)
            try db.execute(
                sql: """
                INSERT INTO messages (
                    session_id, ordinal, role, text, reasoning, tool_calls_json, tool_call_id, tool_name
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
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
                UPDATE messages SET text = ?, reasoning = ?, tool_calls_json = ?
                WHERE id = ?
                """,
                arguments: [message.text, message.reasoning, toolCallsJSON, rowID]
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
