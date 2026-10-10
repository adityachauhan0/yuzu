import Testing
import YuzuHarness

struct MCPConfigTests {
    @Test func parsesEnabledStdioAndDisabledHTTP() throws {
        let json = """
        {
          "mcp_servers": {
            "local": { "command": "/bin/echo", "args": ["hi"], "env": { "A": "b" } },
            "remote": { "enabled": false, "url": "https://example.com/mcp", "headers": { "Authorization": "Bearer x" } }
          }
        }
        """
        let entries = try MCPConfig.parse(json)
        #expect(entries.map(\.name) == ["local", "remote"])
        #expect(entries[0].enabled)
        #expect(entries[0].config.transport == .stdio(command: "/bin/echo", arguments: ["hi"], environment: ["A": "b"]))
        #expect(!entries[1].enabled)
        #expect(entries[1].config.transport == .http(url: "https://example.com/mcp", headers: ["Authorization": "Bearer x"]))
    }

    @Test func enabledEntryNeedsATransport() {
        let json = #"{"mcp_servers":{"bare":{"enabled":true}}}"#
        #expect(throws: MCPConfigError.missingTransport("bare")) {
            try MCPConfig.parse(json)
        }
    }

    @Test func emptyDocumentHasNoServers() throws {
        let entries = try MCPConfig.parse(#"{"mcp_servers":{}}"#)
        #expect(entries.isEmpty)
    }
}
