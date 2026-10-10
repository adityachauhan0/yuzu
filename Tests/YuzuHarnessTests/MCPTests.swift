import Foundation
import Testing
@testable import YuzuHarness

@Suite(.serialized)
struct MCPTests {
    private func fixturesURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
    }

    private func makeWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuzu-mcp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func stdioConfig(
        name: String = "test",
        extraEnvironment: [String: String] = [:]
    ) -> MCPServerConfig {
        MCPServerConfig(
            name: name,
            transport: .stdio(
                command: "/usr/bin/python3",
                arguments: [fixturesURL("mcp_stdio_double.py").path],
                environment: extraEnvironment
            )
        )
    }

    private func makeRunner(
        project: URL,
        turns: [AssistantTurn],
        agentID: String = "build"
    ) throws -> (HarnessStore, SessionRunner, ScriptedTurn, String) {
        let store = try HarnessStore(path: project.appendingPathComponent("session.sqlite").path)
        let sessionID = "session-mcp"
        try store.insertSession(
            SessionRecord(
                id: sessionID,
                projectPath: project.path,
                agentID: agentID,
                modelIdentifier: "test",
                epochID: "epoch-1",
                stepCount: 0,
                supportsMultipleToolCalls: true,
                status: .idle,
                modelMessageCursor: 0
            )
        )
        let script = ScriptedTurn(turns: turns)
        let runner = SessionRunner(sessionID: sessionID, store: store, model: script)
        return (store, runner, script, sessionID)
    }

    private func waitUntil(timeout: TimeInterval, condition: () throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        Issue.record("condition not met before timeout")
    }

    @Test func M1_registersSanitizedName() async throws {
        MCPHub.shared.resetForTests()
        let project = try makeWorkspace()
        defer { MCPHub.shared.resetForTests() }

        try await MCPHub.shared.connect(config: stdioConfig(), projectPath: project.path)

        let materialized = ToolRegistry.materialize(
            agent: .build,
            projectPath: project.path,
            sessionID: "s",
            savedAllows: [],
            manualPressed: true
        )
        let ping = try #require(materialized.definitions.first { $0.name == "mcp_test_ping" })
        #expect(ping.name == "mcp_test_ping")
        #expect(PermissionGate.permissionAction(for: "mcp_test_ping") == "mcp:test")
    }

    @Test func M2_askBeforeCall() async throws {
        MCPHub.shared.resetForTests()
        let project = try makeWorkspace()
        defer { MCPHub.shared.resetForTests() }

        let trace = project.appendingPathComponent("mcp-trace.txt")
        try await MCPHub.shared.connect(
            config: stdioConfig(extraEnvironment: ["MCP_TRACE_FILE": trace.path]),
            projectPath: project.path
        )

        let pingCall = ToolCall(id: "ping-1", name: "mcp_test_ping", arguments: .object([:]))
        let (store, runner, _, sessionID) = try makeRunner(
            project: project,
            turns: [AssistantTurn(text: "", toolCalls: [pingCall]), AssistantTurn(text: "done")]
        )

        _ = try store.appendInbox(sessionID: sessionID, text: "go", delivery: .queue)
        let runTask = Task { await runner.run() }

        try await waitUntil(timeout: 5) {
            !(try store.pendingPermissionRequests(sessionID: sessionID).isEmpty)
        }
        #expect(!FileManager.default.fileExists(atPath: trace.path))

        let pending = try #require(try store.pendingPermissionRequests(sessionID: sessionID).first)
        #expect(pending.action == "mcp:test")
        let asked = try store.harnessEvents(sessionID: sessionID).filter { $0.name == "permission.asked" }
        #expect(asked.count == 1)

        await runner.replyPermission(pending.id, .once)
        await runTask.value

        #expect(FileManager.default.fileExists(atPath: trace.path))
        let tool = try #require(
            try store.messages(sessionID: sessionID).first { $0.role == .tool && $0.toolName == "mcp_test_ping" }
        )
        #expect(tool.text.contains("pong"))
    }

    @Test func M3_disconnectIsStale() async throws {
        MCPHub.shared.resetForTests()
        let project = try makeWorkspace()
        defer { MCPHub.shared.resetForTests() }

        try await MCPHub.shared.connect(config: stdioConfig(), projectPath: project.path)
        MCPHub.shared.disconnect(serverName: "test")

        let pingCall = ToolCall(id: "ping-1", name: "mcp_test_ping", arguments: .object([:]))
        let (store, runner, _, sessionID) = try makeRunner(
            project: project,
            turns: [AssistantTurn(text: "", toolCalls: [pingCall]), AssistantTurn(text: "done")]
        )

        await runner.prompt("go", delivery: .queue)
        await runner.run()

        let tool = try #require(
            try store.messages(sessionID: sessionID).first { $0.role == .tool }
        )
        #expect(tool.text.contains("Stale tool call"))

        let materialized = ToolRegistry.materialize(
            agent: .build,
            projectPath: project.path,
            sessionID: sessionID,
            savedAllows: [],
            manualPressed: true
        )
        #expect(!materialized.allowedNames.contains("mcp_test_ping"))
    }

    @Test func M4_instructionsAreAContextSource() async throws {
        MCPHub.shared.resetForTests()
        let project = try makeWorkspace()
        defer { MCPHub.shared.resetForTests() }
        try "alpha".write(
            to: project.appendingPathComponent("YUZU.md"),
            atomically: true,
            encoding: .utf8
        )

        let (store, runner, script, sessionID) = try makeRunner(
            project: project,
            turns: [AssistantTurn(text: "one"), AssistantTurn(text: "two")]
        )

        await runner.prompt("first", delivery: .queue)
        await runner.run()

        try await MCPHub.shared.connect(
            config: stdioConfig(extraEnvironment: ["MCP_INSTRUCTIONS": "be brief"]),
            projectPath: project.path
        )

        await runner.prompt("second", delivery: .queue)
        await runner.run()

        let systemUpdates = try store.messages(sessionID: sessionID).filter {
            $0.role == .system && $0.text.contains("be brief")
        }
        #expect(!systemUpdates.isEmpty)
        let secondRequest = try #require(script.requests.last)
        let deltaSystem = secondRequest.delta.filter { $0.role == .system }.map(\.text).joined()
        #expect(deltaSystem.contains("be brief"))
    }

    @Test func M5_httpStaticHeader() async throws {
        MCPHub.shared.resetForTests()
        let project = try makeWorkspace()
        defer { MCPHub.shared.resetForTests() }

        let bearer = "slice7-bearer"
        let port = 28_765
        let authTrace = project.appendingPathComponent("http-auth-trace.txt")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [fixturesURL("mcp_http_double.py").path]
        var env = ProcessInfo.processInfo.environment
        env["MCP_HTTP_BEARER"] = bearer
        env["MCP_HTTP_PORT"] = "\(port)"
        env["MCP_HTTP_AUTH_TRACE"] = authTrace.path
        process.environment = env
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { process.terminate() }
        try await Task.sleep(nanoseconds: 300_000_000)

        let url = "http://127.0.0.1:\(port)/"
        try await MCPHub.shared.connect(
            config: MCPServerConfig(
                name: "test",
                transport: .http(url: url, headers: ["Authorization": "Bearer \(bearer)"])
            ),
            projectPath: project.path
        )

        let materialized = ToolRegistry.materialize(
            agent: .build,
            projectPath: project.path,
            sessionID: "s",
            savedAllows: [],
            manualPressed: true
        )
        #expect(materialized.definitions.contains { $0.name == "mcp_test_ping" })

        #expect(FileManager.default.fileExists(atPath: authTrace.path))
        let authLog = try String(contentsOf: authTrace, encoding: .utf8)
        #expect(authLog.contains("Bearer \(bearer)"))
    }
}
