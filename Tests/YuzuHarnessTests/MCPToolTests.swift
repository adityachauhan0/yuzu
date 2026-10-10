import Foundation
import Testing
@testable import YuzuHarness

struct MCPToolTests {
    @Test func installDuckDuckGoUsesTheDefaultNpxPackage() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuzu-mcp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("mcp.json")
        let text = try MCPTool.install(name: "duckduckgo", command: nil, args: [], url: nil, at: file)
        let entries = try MCPConfig.parse(text)
        let server = try #require(entries.first { $0.name == "duckduckgo" })
        guard case .stdio(let command, let args, _) = server.config.transport else {
            Issue.record("DuckDuckGo was not saved as a stdio server")
            return
        }
        #expect(command == "npx")
        #expect(args == ["-y", "duckduckgo-mcp-server"])
        #expect(SkillCatalog.discover(projectPath: root.path).contains { $0.name == "customize-yuzu" && $0.description.contains("DuckDuckGo") })
    }
}
