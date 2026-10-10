import XCTest
import YuzuHarness
@testable import Yuzu

/// Tasks are sessions in the store, not one hardcoded row.
@MainActor
final class TaskSessionTests: XCTestCase {
    private func makeModel(_ turns: [AssistantTurn]) throws -> AppModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuzu-tasks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = try AppModel.makeForTesting(databaseURL: directory.appendingPathComponent("test.sqlite"))
        model.useModel(ScriptedTurn(turns: turns))
        return model
    }

    func testEachCodeSendIsANewTaskAndTheThreadContinuesOne() async throws {
        let model = try makeModel([
            AssistantTurn(text: "first answer"),
            AssistantTurn(text: "second answer"),
            AssistantTurn(text: "follow-up answer"),
        ])
        model.selectCode()
        await model.sendPrompt("fix the parser", newTask: true)
        XCTAssertEqual(model.codeTaskPreview, "fix the parser")
        let first = model.sessionID
        await model.sendPrompt("write the docs", newTask: true)
        let second = model.sessionID
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(model.taskSessions.map(\.displayTitle), ["write the docs", "fix the parser"])

        model.openTask(first)
        XCTAssertEqual(model.workspaceMode, .code)
        XCTAssertTrue(model.codeThreadOpen)
        XCTAssertEqual(model.transcript.map(\.text), ["fix the parser", "first answer"])
        await model.sendPrompt("and the tests")
        XCTAssertEqual(model.sessionID, first)
        let conversation = { (id: String) in
            try model.store.messages(sessionID: id).filter { $0.role == .user || $0.role == .assistant }.map(\.text)
        }
        XCTAssertEqual(try conversation(first), ["fix the parser", "first answer", "and the tests", "follow-up answer"])
        XCTAssertEqual(try conversation(second), ["write the docs", "second answer"])
    }

    func testRenamePinAndDeleteActOnTheOpenTask() async throws {
        let model = try makeModel([AssistantTurn(text: "a"), AssistantTurn(text: "b")])
        await model.sendPrompt("one", newTask: true)
        let one = model.sessionID
        await model.sendPrompt("two", newTask: true)
        model.openTask(one)
        model.renameCurrentTask("Parser work")
        model.togglePinCurrentTask()
        XCTAssertEqual(model.taskTitle, "Parser work")
        XCTAssertEqual(model.pinnedSessions.map(\.displayTitle), ["Parser work"])
        XCTAssertTrue(model.hasPinnedItems)

        model.deleteCurrentTask()
        XCTAssertNil(try model.store.session(id: one))
        XCTAssertEqual(model.taskSessions.map(\.displayTitle), ["two"])
        XCTAssertFalse(model.hasPinnedItems)
    }

    func testUsageComesFromTheStore() async throws {
        let model = try makeModel([
            AssistantTurn(text: "a", outputTokens: 30),
            AssistantTurn(text: "b", outputTokens: 10),
        ])
        await model.sendPrompt("one", newTask: true)
        await model.sendPrompt("two", newTask: true)
        let metrics = model.usageMetrics(period: .days7)
        XCTAssertEqual(metrics.sessions, 2)
        XCTAssertEqual(metrics.messages, 4)
        XCTAssertEqual(metrics.tokens, 40)
        XCTAssertEqual(metrics.activeDays, 1)
        XCTAssertNotEqual(metrics.peakHour, "—")
        XCTAssertEqual(model.activityLevels().last, 2, "Today is the busiest day.")
        XCTAssertEqual(model.activityLevels().dropLast().filter { $0 > 0 }.count, 0)
        XCTAssertEqual(model.activityLevels().count, 26)
        XCTAssertEqual(model.modelShares(period: .all).map(\.share), [1])
    }

    func testActivityLineCountsOneSettlement() {
        let bash1 = ToolCall(id: "1", name: "bash", arguments: .object(["command": .string("ls")]))
        let bash2 = ToolCall(id: "2", name: "bash", arguments: .object(["command": .string("pwd")]))
        let plan = ToolCall(id: "3", name: "todowrite", arguments: .object([:]))
        let read = ToolCall(id: "4", name: "read", arguments: .object(["path": .string("a.txt")]))
        let items = ThreadItem.build([
            .user("go"),
            .assistant(AssistantTurn(text: "", toolCalls: [plan, bash1, bash2])),
            .toolResult(id: "3", name: "todowrite", text: "Updated tasks: 0 of 1 done."),
            .toolResult(id: "1", name: "bash", text: "Ran: ls"),
            .toolResult(id: "2", name: "bash", text: "Ran: pwd"),
            .assistant(AssistantTurn(text: "", toolCalls: [read])),
            .toolResult(id: "4", name: "read", text: "hi"),
            .assistant(AssistantTurn(text: "done")),
        ])
        XCTAssertEqual(items.count, 4)
        guard case .tools(let grouped, let groupRows) = items[1], case .tools(let single, let readRows) = items[2] else {
            return XCTFail("Expected two tool settlements, got \(items)")
        }
        XCTAssertEqual(grouped, ToolRowFormatter.groupLabel(toolCount: 3))
        XCTAssertEqual(groupRows.map(\.call.name), ["todowrite", "bash", "bash"])
        XCTAssertEqual(single, "Read a.txt")
        XCTAssertEqual(readRows.count, 1)
        XCTAssertEqual(readRows[0].presentation.detail, "a.txt")
        guard case .reply(let done) = items[3] else {
            return XCTFail("Expected reply")
        }
        XCTAssertEqual(done, "done")
    }
}
