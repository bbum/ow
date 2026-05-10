import Foundation

/// Protocol for MCP tools. Each tool may receive a default scope config from
/// the server (nil if no host is configured); tools that take host/port may
/// override per-call via their input schema.
protocol MCPTool {
    static var name: String { get }
    static var description: String { get }
    static var inputSchema: JSONValue { get }

    init(scope: ScopeConfig?)

    func execute(args: [String: JSONValue]) async throws -> [JSONValue]
}

extension MCPTool {
    static var mcpToolDefinition: JSONValue {
        .object([
            "name": .string(name),
            "description": .string(description),
            "inputSchema": inputSchema
        ])
    }
}

/// Helper to read an optional scope override out of MCP tool args, falling back
/// to a server-supplied default. Returns nil if no host can be resolved — let
/// the caller surface a helpful "no host configured" message to the LLM.
func resolveScope(args: [String: JSONValue], default defaultConfig: ScopeConfig?) -> ScopeConfig? {
    let argHost = args["host"]?.stringValue
    let argPort = args["port"]?.intValue.flatMap { $0 > 0 && $0 <= Int(UInt16.max) ? UInt16($0) : nil }
    guard let host = argHost ?? defaultConfig?.host else { return nil }
    let port = argPort ?? defaultConfig?.port ?? 3000
    return ScopeConfig(host: host, port: port)
}

/// Standard error block returned when a tool needs a scope host but none was
/// supplied per-call and none is configured globally. The wording is meant for
/// an LLM to read aloud back to the user.
let noHostBlock: JSONValue = textBlock("""
    No scope host is configured.

    Either:
      - Pass `host` (e.g. "10.0.1.230") to this tool call, or
      - Set a default once on the command line:  ow config set host <ip>

    The MCP server will then use that host for every tool call. The CLI also \
    accepts --host <ip> for one-off use.
    """)

/// Common JSON Schema fragment for the host/port overrides every capture tool accepts.
let scopeOverrideProperties: [String: JSONValue] = [
    "host": .object([
        "type": .string("string"),
        "description": .string("Override scope IP address (default: configured net.bbum.ow host).")
    ]),
    "port": .object([
        "type": .string("integer"),
        "description": .string("Override scope TCP port (default: 3000).")
    ])
]
