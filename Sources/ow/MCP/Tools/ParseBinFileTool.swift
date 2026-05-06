import Foundation

struct ParseBinFileTool: MCPTool {
    static let name = "parse_bin_file"

    static let description = """
        Parse a previously-saved Owon .bin file (live network format or USB-saved format)
        and return the structured contents as JSON. Same response shape as capture_waveform.

        Use this to: re-analyze an old capture, compare captures, share waveform data without
        re-hitting the scope.
        """

    static let inputSchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "path": .object([
                "type": .string("string"),
                "description": .string("Path to the .bin file (tilde expansion supported).")
            ]),
            "include_samples": .object([
                "type": .string("boolean"),
                "description": .string("Return every sample as a numeric array (default false).")
            ]),
            "decimate": .object([
                "type": .string("integer"),
                "description": .string("Return every Nth sample. Mutually exclusive with include_samples.")
            ])
        ]),
        "required": .array([.string("path")])
    ])

    init(scope: ScopeConfig) {} // path-based; no scope needed

    func execute(args: [String: JSONValue]) async throws -> [JSONValue] {
        guard let path = args["path"]?.stringValue else {
            throw MCPToolError.missingArg("path")
        }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let data = try Data(contentsOf: url)
        let bin = try BinFile.parse(data)
        let json = waveformJSON(bin: bin, args: args)
        let pretty = try JSONEncoder.prettyEncoded(json)
        return [textBlock(pretty)]
    }
}

enum MCPToolError: Error, CustomStringConvertible {
    case missingArg(String)

    var description: String {
        switch self {
        case .missingArg(let name): return "missing required argument: \(name)"
        }
    }
}
