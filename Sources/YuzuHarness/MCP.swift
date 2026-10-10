import Foundation
import os

public enum MCPServerTransport: Sendable, Equatable, Codable {
    case stdio(command: String, arguments: [String], environment: [String: String])
    case http(url: String, headers: [String: String])
}

public struct MCPServerConfig: Sendable, Equatable {
    public var name: String
    public var transport: MCPServerTransport
    public var timeout: TimeInterval

    public init(name: String, transport: MCPServerTransport, timeout: TimeInterval = 30) {
        self.name = name
        self.transport = transport
        self.timeout = timeout
    }

    public func addingBearerToken(_ token: String) -> MCPServerConfig {
        switch transport {
        case .http(let url, var headers):
            headers["Authorization"] = "Bearer \(token)"
            return MCPServerConfig(name: name, transport: .http(url: url, headers: headers), timeout: timeout)
        case .stdio:
            return self
        }
    }
}

public enum MCPConnectionStatus: Sendable, Equatable {
    case connected
    case failed(String)
    case needsAuth
}

public struct MCPRegisteredTool: Sendable, Equatable {
    public var harnessName: String
    public var serverName: String
    public var toolName: String
    public var definition: ToolDefinition
    public var permissionAction: String
}

// MARK: - Hub

public final class MCPHub: @unchecked Sendable {
    public static let shared = MCPHub()

    private struct ServerState {
        var config: MCPServerConfig
        var session: MCPSession
        var tools: [MCPRegisteredTool]
        var instructions: String?
        var prompts: [MCPPromptDescriptor]
        var resources: [MCPResourceDescriptor]
    }

    private struct HubState {
        var servers: [String: ServerState] = [:]
        var staleHarnessNames: Set<String> = []
        var needsAuthServers: Set<String> = []
        var authorizationURIs: [String: String] = [:]
        var tokenURIs: [String: String] = [:]
        var pendingConfigs: [String: MCPServerConfig] = [:]
    }

    private let lock = OSAllocatedUnfairLock(initialState: HubState())
    private var nextRequestID = 1

    public func connect(config: MCPServerConfig, projectPath: String) async throws {
        let session: MCPSession
        switch config.transport {
        case .stdio(let command, let arguments, let environment):
            session = try MCPStdioSession(
                command: command,
                arguments: arguments,
                environment: environment,
                cwd: projectPath,
                timeout: config.timeout
            )
        case .http(let url, let headers):
            session = MCPHTTPSession(urlString: url, headers: headers, timeout: config.timeout)
        }

        do {
            try await finishConnect(config: config, session: session, projectPath: projectPath)
        } catch let MCPError.needsAuthentication(challenge) {
            lock.withLock { state in
                state.needsAuthServers.insert(config.name)
                state.pendingConfigs[config.name] = config
                if let uri = challenge.authorizationURI {
                    state.authorizationURIs[config.name] = uri
                }
                if let tokenURI = challenge.tokenURI {
                    state.tokenURIs[config.name] = tokenURI
                }
                session.close()
            }
        }
    }

    private func finishConnect(
        config: MCPServerConfig,
        session: MCPSession,
        projectPath: String
    ) async throws {
        let initResult = try await session.initialize(projectPath: projectPath)
        let listResult = try await session.toolsList()
        let promptList = (try? await session.promptsList()) ?? []
        let resourceList = (try? await session.resourcesList()) ?? []

        let serverTools = listResult.map { tool in
            let harnessName = MCPNaming.harnessName(server: config.name, tool: tool.name)
            let action = "mcp:\(config.name)"
            return MCPRegisteredTool(
                harnessName: harnessName,
                serverName: config.name,
                toolName: tool.name,
                definition: ToolDefinition(
                    name: harnessName,
                    description: tool.description,
                    parameters: tool.inputSchema
                ),
                permissionAction: action
            )
        }

        lock.withLock { state in
            state.needsAuthServers.remove(config.name)
            for tool in serverTools {
                state.staleHarnessNames.remove(tool.harnessName)
            }
            state.servers[config.name] = ServerState(
                config: config,
                session: session,
                tools: serverTools,
                instructions: initResult.instructions,
                prompts: promptList,
                resources: resourceList
            )
        }
    }

    public func disconnect(serverName: String) {
        lock.withLock { state in
            guard let server = state.servers.removeValue(forKey: serverName) else { return }
            for tool in server.tools {
                state.staleHarnessNames.insert(tool.harnessName)
            }
            server.session.close()
        }
    }

    public func status(serverName: String) -> MCPConnectionStatus? {
        lock.withLock { state in
            if state.needsAuthServers.contains(serverName) {
                return .needsAuth
            }
            guard state.servers[serverName] != nil else { return nil }
            return .connected
        }
    }

    public func promptNames(serverName: String) -> [String] {
        lock.withLock { state in
            state.servers[serverName]?.prompts.map(\.name) ?? []
        }
    }

    public func authorizationURI(serverName: String) -> String? {
        lock.withLock { state in
            state.authorizationURIs[serverName]
        }
    }

    public func tokenURI(serverName: String) -> String? {
        lock.withLock { state in
            state.tokenURIs[serverName]
        }
    }

    public func pendingConfig(serverName: String) -> MCPServerConfig? {
        lock.withLock { state in
            state.pendingConfigs[serverName]
        }
    }

    public func serverName(forPrompt name: String) -> String? {
        lock.withLock { state in
            for server in state.servers.values {
                if server.prompts.contains(where: { $0.name == name }) {
                    return server.config.name
                }
            }
            return nil
        }
    }

    public func getPromptText(serverName: String, name: String) async throws -> String {
        let session = lock.withLock { state -> MCPSession? in
            state.servers[serverName]?.session
        }
        guard let session else {
            throw MCPError.requestFailed("server not connected")
        }
        return try await session.promptsGet(name: name)
    }

    public func hasExposedResources() -> Bool {
        lock.withLock { state in
            state.servers.values.contains { !$0.resources.isEmpty }
        }
    }

    public func isReadResourceWhollyDenied(agentID: String) -> Bool {
        let servers = lock.withLock { state in
            state.servers.values.filter { !$0.resources.isEmpty }.map(\.config.name)
        }
        guard !servers.isEmpty else { return true }
        return servers.allSatisfy { server in
            PermissionGate.isWhollyDenied(agentID: agentID, action: "mcp:\(server)")
        }
    }

    public func serverName(forResourceURI uri: String?) -> String? {
        guard let uri else { return nil }
        return lock.withLock { state -> String? in
            for server in state.servers.values {
                if server.resources.contains(where: { $0.uri == uri }) {
                    return server.config.name
                }
            }
            return nil
        }
    }

    public func readResource(uri: String) async -> String {
        let sessionPair = lock.withLock { state -> (MCPSession, String)? in
            for server in state.servers.values {
                if server.resources.contains(where: { $0.uri == uri }) {
                    return (server.session, server.config.name)
                }
            }
            return nil
        }
        guard let (session, _) = sessionPair else {
            return "Unknown resource"
        }
        do {
            return try await session.resourcesRead(uri: uri)
        } catch {
            return "MCP error: \(error.localizedDescription)"
        }
    }

    public func registeredTools() -> [MCPRegisteredTool] {
        lock.withLock { state in
            state.servers.values.flatMap(\.tools)
        }
    }

    public func connectedServerNames() -> [String] {
        lock.withLock { state in
            state.servers.keys.sorted()
        }
    }

    public func instructionsText() -> String? {
        lock.withLock { state in
            let parts = state.servers.values.compactMap { server -> String? in
                guard let instructions = server.instructions, !instructions.isEmpty else { return nil }
                return "\(server.config.name):\n\(instructions)"
            }
            guard !parts.isEmpty else { return nil }
            return parts.joined(separator: "\n\n")
        }
    }

    public func permissionAction(forHarnessName name: String) -> String? {
        lock.withLock { state in
            for server in state.servers.values {
                if let tool = server.tools.first(where: { $0.harnessName == name }) {
                    return tool.permissionAction
                }
            }
            return nil
        }
    }

    public func mcpResource(forHarnessName name: String) -> String? {
        lock.withLock { state in
            for server in state.servers.values {
                if let tool = server.tools.first(where: { $0.harnessName == name }) {
                    return tool.toolName
                }
            }
            return nil
        }
    }

    public func isStaleHarnessName(_ name: String) -> Bool {
        lock.withLock { $0.staleHarnessNames.contains(name) }
    }

    public func toolsForMaterialize(agentID: String) -> [MCPRegisteredTool] {
        let tools = registeredTools()
        return tools.filter { tool in
            !PermissionGate.isWhollyDenied(agentID: agentID, action: tool.permissionAction)
        }
    }

    public func execute(harnessName: String, arguments: JSONValue) async -> String {
        let sessionAndTool = lock.withLock { state -> (MCPSession, String)? in
            for server in state.servers.values {
                if let tool = server.tools.first(where: { $0.harnessName == harnessName }) {
                    return (server.session, tool.toolName)
                }
            }
            return nil
        }
        guard let (session, toolName) = sessionAndTool else {
            return "Stale tool call"
        }
        do {
            return try await session.toolsCall(name: toolName, arguments: arguments)
        } catch {
            return "MCP error: \(error.localizedDescription)"
        }
    }

    /// Test isolation: drop every connection and stale markers.
    public func resetForTests() {
        lock.withLock { state in
            for server in state.servers.values {
                server.session.close()
            }
            state.servers = [:]
            state.staleHarnessNames = []
            state.needsAuthServers = []
            state.authorizationURIs = [:]
            state.tokenURIs = [:]
            state.pendingConfigs = [:]
        }
    }
}

// MARK: - Naming

enum MCPNaming {
    static func sanitizeComponent(_ name: String) -> String {
        var result = ""
        for character in name {
            if character.isLetter || character.isNumber || character == "_" || character == "-" {
                result.append(character)
            } else {
                result.append("_")
            }
        }
        if result.isEmpty || result.first?.isLetter != true {
            result = "x" + result
        }
        if result.count > 63 {
            result = String(result.prefix(63))
        }
        return result
    }

    static func harnessName(server: String, tool: String) -> String {
        let combined = "mcp_\(sanitizeComponent(server))_\(sanitizeComponent(tool))"
        if combined.count > 64 {
            return String(combined.prefix(64))
        }
        return combined
    }
}

// MARK: - Session protocol

struct MCPInitializeResult: Sendable {
    var instructions: String?
}

struct MCPToolDescriptor: Sendable {
    var name: String
    var description: String
    var inputSchema: JSONValue
}

struct MCPPromptDescriptor: Sendable {
    var name: String
}

struct MCPResourceDescriptor: Sendable {
    var uri: String
    var name: String
}

protocol MCPSession: Sendable {
    func initialize(projectPath: String) async throws -> MCPInitializeResult
    func toolsList() async throws -> [MCPToolDescriptor]
    func toolsCall(name: String, arguments: JSONValue) async throws -> String
    func promptsList() async throws -> [MCPPromptDescriptor]
    func promptsGet(name: String) async throws -> String
    func resourcesList() async throws -> [MCPResourceDescriptor]
    func resourcesRead(uri: String) async throws -> String
    func close()
}

// MARK: - JSON-RPC helpers

enum MCPJSON {
    static func encodeRequest(id: Int, method: String, params: [String: Any]?) throws -> Data {
        var object: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
        ]
        if let params {
            object["params"] = params
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    static func encodeNotification(method: String, params: [String: Any]?) throws -> Data {
        var object: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
        ]
        if let params {
            object["params"] = params
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    static func parseResponse(_ data: Data) throws -> (id: Int?, result: [String: Any]?, error: String?) {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPError.invalidResponse
        }
        let id = json["id"] as? Int
        if let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "unknown error"
            return (id, nil, message)
        }
        let result = json["result"] as? [String: Any]
        return (id, result, nil)
    }

    static func jsonValue(from object: Any) -> JSONValue {
        switch object {
        case is NSNull:
            return .null
        case let value as Bool:
            return .bool(value)
        case let value as Int:
            return .number(Double(value))
        case let value as Double:
            return .number(value)
        case let value as String:
            return .string(value)
        case let array as [Any]:
            return .array(array.map { jsonValue(from: $0) })
        case let dict as [String: Any]:
            return .object(dict.mapValues { jsonValue(from: $0) })
        default:
            return .null
        }
    }
}

enum MCPError: Error {
    case invalidResponse
    case requestFailed(String)
    case timedOut
    case processFailed
    case needsAuthentication(OAuthAuthorization)
}

// MARK: - Stdio transport

final class MCPStdioSession: MCPSession, @unchecked Sendable {
    private let process: Process
    private let stdinHandle: FileHandle
    private let readQueue = DispatchQueue(label: "mcp.stdio.read")
    private let lock = OSAllocatedUnfairLock(initialState: StdioState())
    private let timeout: TimeInterval

    private struct StdioState {
        var nextID = 1
        var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
        var buffer = Data()
        var closed = false
    }

    init(command: String, arguments: [String], environment: [String: String], cwd: String, timeout: TimeInterval) throws {
        self.timeout = timeout
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            env[key] = value
        }
        process.environment = env
        process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()

        try process.run()
        self.process = process
        self.stdinHandle = stdinPipe.fileHandleForWriting

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self?.appendStdout(data)
        }
    }

    private func appendStdout(_ data: Data) {
        guard !data.isEmpty else { return }
        let lines: [Data] = lock.withLock { state -> [Data] in
            state.buffer.append(data)
            var extracted: [Data] = []
            while let newline = state.buffer.firstIndex(of: 0x0A) {
                let line = state.buffer[..<newline]
                state.buffer.removeSubrange(...newline)
                if !line.isEmpty {
                    extracted.append(Data(line))
                }
            }
            return extracted
        }
        for line in lines {
            dispatchResponse(line)
        }
    }

    private func dispatchResponse(_ line: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        if let id = json["id"] as? Int {
            let continuation = lock.withLock { state -> CheckedContinuation<[String: Any], Error>? in
                state.pending.removeValue(forKey: id)
            }
            if let error = json["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "error"
                continuation?.resume(throwing: MCPError.requestFailed(message))
                return
            }
            if let result = json["result"] as? [String: Any] {
                continuation?.resume(returning: result)
            }
        }
    }

    private func request(method: String, params: [String: Any]?) async throws -> [String: Any] {
        let id = lock.withLock { state -> Int in
            let value = state.nextID
            state.nextID += 1
            return value
        }
        let payload = try MCPJSON.encodeRequest(id: id, method: method, params: params)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: Any], Error>) in
            lock.withLock { state in
                state.pending[id] = continuation
            }
            stdinHandle.write(payload)
            stdinHandle.write(Data([0x0A]))
        }
    }

    private func notify(method: String, params: [String: Any]?) throws {
        let payload = try MCPJSON.encodeNotification(method: method, params: params)
        stdinHandle.write(payload)
        stdinHandle.write(Data([0x0A]))
    }

    func initialize(projectPath: String) async throws -> MCPInitializeResult {
        let result = try await request(
            method: "initialize",
            params: [
                "protocolVersion": "2024-11-05",
                "capabilities": [:],
                "clientInfo": ["name": "yuzu-harness", "version": "1.0"],
            ]
        )
        try notify(method: "notifications/initialized", params: nil)
        let instructions = result["instructions"] as? String
        return MCPInitializeResult(instructions: instructions)
    }

    func toolsList() async throws -> [MCPToolDescriptor] {
        let result = try await request(method: "tools/list", params: [:])
        guard let tools = result["tools"] as? [[String: Any]] else { return [] }
        return tools.compactMap { tool in
            guard let name = tool["name"] as? String else { return nil }
            let description = tool["description"] as? String ?? ""
            let schema = MCPJSON.jsonValue(from: tool["inputSchema"] ?? ["type": "object"])
            return MCPToolDescriptor(name: name, description: description, inputSchema: schema)
        }
    }

    func toolsCall(name: String, arguments: JSONValue) async throws -> String {
        let argsObject: [String: Any]
        if case .object(let object) = arguments {
            argsObject = object.mapValues { jsonValueToAny($0) }
        } else {
            argsObject = [:]
        }
        let result = try await request(
            method: "tools/call",
            params: [
                "name": name,
                "arguments": argsObject,
            ]
        )
        return extractToolText(result)
    }

    func promptsList() async throws -> [MCPPromptDescriptor] {
        let result = try await request(method: "prompts/list", params: [:])
        guard let prompts = result["prompts"] as? [[String: Any]] else { return [] }
        return prompts.compactMap { item in
            guard let name = item["name"] as? String else { return nil }
            return MCPPromptDescriptor(name: name)
        }
    }

    func promptsGet(name: String) async throws -> String {
        let result = try await request(method: "prompts/get", params: ["name": name])
        return extractPromptText(result)
    }

    func resourcesList() async throws -> [MCPResourceDescriptor] {
        let result = try await request(method: "resources/list", params: [:])
        guard let resources = result["resources"] as? [[String: Any]] else { return [] }
        return resources.compactMap { item in
            guard let uri = item["uri"] as? String else { return nil }
            let name = item["name"] as? String ?? uri
            return MCPResourceDescriptor(uri: uri, name: name)
        }
    }

    func resourcesRead(uri: String) async throws -> String {
        let result = try await request(method: "resources/read", params: ["uri": uri])
        return extractResourceText(result)
    }

    func close() {
        lock.withLock { state in
            state.closed = true
            for (_, continuation) in state.pending {
                continuation.resume(throwing: MCPError.processFailed)
            }
            state.pending = [:]
        }
        stdinHandle.closeFile()
        if process.isRunning {
            process.terminate()
        }
    }
}

// MARK: - HTTP transport

final class MCPHTTPSession: MCPSession, @unchecked Sendable {
    private let url: URL
    private let headers: [String: String]
    private let timeout: TimeInterval
    private var nextID = 1

    init(urlString: String, headers: [String: String], timeout: TimeInterval) {
        self.url = URL(string: urlString)!
        self.headers = headers
        self.timeout = timeout
    }

    private func postNotification(method: String, params: [String: Any]?) async throws {
        let payload = try MCPJSON.encodeNotification(method: method, params: params)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        _ = try await URLSession.shared.data(for: request)
    }

    private func post(method: String, params: [String: Any]?) async throws -> [String: Any] {
        let id = nextID
        nextID += 1
        let body = try MCPJSON.encodeRequest(id: id, method: method, params: params)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            let challenge = http.value(forHTTPHeaderField: "WWW-Authenticate") ?? ""
            if !challenge.isEmpty {
                throw MCPError.needsAuthentication(OAuthChallenge.parse(challenge))
            }
            throw MCPError.requestFailed("unauthorized")
        }
        let parsed = try MCPJSON.parseResponse(data)
        if let error = parsed.error {
            throw MCPError.requestFailed(error)
        }
        return parsed.result ?? [:]
    }

    func initialize(projectPath: String) async throws -> MCPInitializeResult {
        let result = try await post(
            method: "initialize",
            params: [
                "protocolVersion": "2024-11-05",
                "capabilities": [:],
                "clientInfo": ["name": "yuzu-harness", "version": "1.0"],
            ]
        )
        try await postNotification(method: "notifications/initialized", params: nil)
        return MCPInitializeResult(instructions: result["instructions"] as? String)
    }

    func toolsList() async throws -> [MCPToolDescriptor] {
        let result = try await post(method: "tools/list", params: [:])
        guard let tools = result["tools"] as? [[String: Any]] else { return [] }
        return tools.compactMap { tool in
            guard let name = tool["name"] as? String else { return nil }
            let description = tool["description"] as? String ?? ""
            let schema = MCPJSON.jsonValue(from: tool["inputSchema"] ?? ["type": "object"])
            return MCPToolDescriptor(name: name, description: description, inputSchema: schema)
        }
    }

    func toolsCall(name: String, arguments: JSONValue) async throws -> String {
        let argsObject: [String: Any]
        if case .object(let object) = arguments {
            argsObject = object.mapValues { jsonValueToAny($0) }
        } else {
            argsObject = [:]
        }
        let result = try await post(
            method: "tools/call",
            params: [
                "name": name,
                "arguments": argsObject,
            ]
        )
        return extractToolText(result)
    }

    func promptsList() async throws -> [MCPPromptDescriptor] {
        let result = try await post(method: "prompts/list", params: [:])
        guard let prompts = result["prompts"] as? [[String: Any]] else { return [] }
        return prompts.compactMap { item in
            guard let name = item["name"] as? String else { return nil }
            return MCPPromptDescriptor(name: name)
        }
    }

    func promptsGet(name: String) async throws -> String {
        let result = try await post(method: "prompts/get", params: ["name": name])
        return extractPromptText(result)
    }

    func resourcesList() async throws -> [MCPResourceDescriptor] {
        let result = try await post(method: "resources/list", params: [:])
        guard let resources = result["resources"] as? [[String: Any]] else { return [] }
        return resources.compactMap { item in
            guard let uri = item["uri"] as? String else { return nil }
            let name = item["name"] as? String ?? uri
            return MCPResourceDescriptor(uri: uri, name: name)
        }
    }

    func resourcesRead(uri: String) async throws -> String {
        let result = try await post(method: "resources/read", params: ["uri": uri])
        return extractResourceText(result)
    }

    func close() {}
}

// MARK: - Shared helpers

private func extractToolText(_ result: [String: Any]) -> String {
    guard let content = result["content"] as? [[String: Any]] else { return "" }
    let parts = content.compactMap { item -> String? in
        guard (item["type"] as? String) == "text" else { return nil }
        return item["text"] as? String
    }
    return parts.joined(separator: "\n")
}

private func extractPromptText(_ result: [String: Any]) -> String {
    if let messages = result["messages"] as? [[String: Any]] {
        let parts = messages.compactMap { item -> String? in
            guard (item["role"] as? String) == "user",
                  let content = item["content"] as? [String: Any],
                  (content["type"] as? String) == "text",
                  let text = content["text"] as? String else { return nil }
            return text
        }
        if !parts.isEmpty {
            return parts.joined(separator: "\n")
        }
    }
    return extractToolText(result)
}

private func extractResourceText(_ result: [String: Any]) -> String {
    if let contents = result["contents"] as? [[String: Any]] {
        let parts = contents.compactMap { item -> String? in
            if let text = item["text"] as? String {
                return text
            }
            guard (item["type"] as? String) == "text",
                  let text = item["text"] as? String else { return nil }
            return text
        }
        if !parts.isEmpty {
            return parts.joined(separator: "\n")
        }
    }
    return extractToolText(result)
}

private func jsonValueToAny(_ value: JSONValue) -> Any {
    switch value {
    case .null:
        return NSNull()
    case .bool(let flag):
        return flag
    case .number(let number):
        return number
    case .string(let string):
        return string
    case .array(let array):
        return array.map { jsonValueToAny($0) }
    case .object(let object):
        return object.mapValues { jsonValueToAny($0) }
    }
}
