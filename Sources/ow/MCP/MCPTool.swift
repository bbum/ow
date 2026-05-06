import Foundation

/// Protocol for MCP tools. Each tool gets a default scope config from the server;
/// tools that take a host/port may override per-call via their input schema.
protocol MCPTool {
    static var name: String { get }
    static var description: String { get }
    static var inputSchema: JSONValue { get }

    init(scope: ScopeConfig)

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
/// to a server-supplied default.
func resolveScope(args: [String: JSONValue], default defaultConfig: ScopeConfig) -> ScopeConfig {
    var config = defaultConfig
    if let host = args["host"]?.stringValue { config.host = host }
    if let port = args["port"]?.intValue, port > 0, port <= Int(UInt16.max) {
        config.port = UInt16(port)
    }
    return config
}

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
