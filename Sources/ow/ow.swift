import ArgumentParser
import Foundation

@main
struct Ow: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ow",
        abstract: "Drive an Owon SDS-series oscilloscope from the command line or expose it as an MCP server.",
        version: "2.0.0",
        subcommands: [
            ScreenCommand.self,
            DataCommand.self,
            MemDepthCommand.self,
            BinCommand.self,
            ConfigCommand.self,
            StatusCommand.self,
            MCPCommand.self,
        ]
    )
}

/// Connection options shared by every command that talks to the scope.
struct ScopeOptions: ParsableArguments {
    @Option(name: .long, help: "Scope IP address. Falls back to net.bbum.ow defaults.")
    var host: String?

    @Option(name: .long, help: "Scope TCP port. Defaults to 3000 (or net.bbum.ow defaults).")
    var port: UInt16?

    func resolve() throws -> ScopeConfig {
        try ScopeDefaults.resolve(hostOverride: host, portOverride: port)
    }
}
