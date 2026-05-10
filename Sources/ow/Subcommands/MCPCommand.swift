import ArgumentParser
import Foundation

struct MCPCommand: AsyncParsableCommand {
    static let configuration: CommandConfiguration = {
        // Resolve the running binary's absolute, symlink-free path so the
        // emitted JSON config block points at the binary the user actually
        // installed (~/.local/bin/ow, an iCloud bin/, /opt/homebrew/bin/ow,
        // etc.) without making them edit it.
        let resolvedPath: String = {
            if let url = Bundle.main.executableURL?.resolvingSymlinksInPath() {
                return url.path
            }
            return CommandLine.arguments.first ?? "ow"
        }()
        let escapedPath = resolvedPath.replacingOccurrences(of: "\\", with: "\\\\")
                                      .replacingOccurrences(of: "\"", with: "\\\"")

        return CommandConfiguration(
            commandName: "mcp",
            abstract: "Run as an MCP server (JSON-RPC over stdio).",
            discussion: """
            By default, all tools are enabled: \(MCPTools.allNames.sorted().joined(separator: ", "))

            Optionally specify tool names to enable only those tools:
              ow mcp scope_status                    # Only TCP/identity probe
              ow mcp capture_screenshot              # Only display capture
              ow mcp capture_waveform parse_bin_file # Live capture + offline parse

            === Tools ===

            scope_status         TCP probe + (optional) identify. Returns model,
                                 serial, channel, frequency. Pass quick=true for
                                 TCP-only.

            capture_screenshot   STARTBMP. Returns PNG inline (~21 KB) so an LLM
                                 can view the scope's display. Optional save_path.

            capture_waveform     STARTBIN (or STARTMEMDEPTH if deep_memory=true).
                                 Returns parsed JSON. Defaults to summary stats
                                 (min/max/mean/Vpp); set include_samples=true for
                                 full sample arrays, or decimate=N for every Nth.

            parse_bin_file       Parse a saved .bin file from disk. Same JSON
                                 shape as capture_waveform.

            All capture tools accept host/port overrides per-call. Defaults come
            from net.bbum.ow (set via `ow config set host …`).

            === MCP Client Configuration ===

            Drop this entry into any MCP-compatible client's config (Claude Code,
            Claude Desktop, Cursor, Continue, Zed, etc.). Path is the absolute
            location of this binary:

            {
              "mcpServers": {
                "ow": {
                  "command": "\(escapedPath)",
                  "args": ["mcp"]
                }
              }
            }

            For specific tools only, append their names to args:
              "args": ["mcp", "capture_waveform"]

            === Defaults ===

            The default scope host/port come from `net.bbum.ow` user defaults.
            Set them once and the MCP server (and CLI) will use them:

              ow config set host 10.0.1.230
              ow config set port 3000

            Per-call host/port arguments to each tool override the defaults.
            Set OW_DEBUG=1 in the server's environment to log connection-level
            traces to stderr.
            """
        )
    }()

    @OptionGroup var scope: ScopeOptions

    @Argument(help: "Tools to enable (default: all). Names: \(MCPTools.allNames.sorted().joined(separator: ", "))")
    var tools: [String] = []

    mutating func run() async throws {
        // Resolve config lazily — an MCP server is a long-lived process that
        // an LLM driver expects to stay up. If no host is configured, the
        // server still starts; tools that need a host will tell the caller
        // (the LLM, and through it the user) how to set one.
        let config = try? scope.resolve()
        let enabled = tools.isEmpty ? MCPTools.allNames : Set(tools.map { $0.lowercased() })
        let server = MCPServer(scope: config, enabledTools: enabled)
        await server.run()
    }
}
