import ArgumentParser
import Foundation

struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Run as an MCP server (JSON-RPC over stdio)."
    )

    @OptionGroup var scope: ScopeOptions

    @Argument(help: "Tools to enable (default: all). Names: \(MCPTools.allNames.sorted().joined(separator: ", "))")
    var tools: [String] = []

    mutating func run() async throws {
        // Resolve config eagerly so a misconfigured server fails fast at startup
        // rather than on the first tool call.
        let config = try scope.resolve()
        let enabled = tools.isEmpty ? MCPTools.allNames : Set(tools.map { $0.lowercased() })
        let server = MCPServer(scope: config, enabledTools: enabled)
        await server.run()
    }
}
