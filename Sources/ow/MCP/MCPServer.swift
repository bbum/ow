import Foundation

enum MCPTools {
    static let allNames: Set<String> = [
        "scope_status",
        "capture_screenshot",
        "capture_waveform",
        "parse_bin_file",
    ]

    static func createTool(name: String, scope: ScopeConfig?) -> (any MCPTool)? {
        switch name {
        case "scope_status": return ScopeStatusTool(scope: scope)
        case "capture_screenshot": return CaptureScreenshotTool(scope: scope)
        case "capture_waveform": return CaptureWaveformTool(scope: scope)
        case "parse_bin_file": return ParseBinFileTool(scope: scope)
        default: return nil
        }
    }

    static func toolType(name: String) -> (any MCPTool.Type)? {
        switch name {
        case "scope_status": return ScopeStatusTool.self
        case "capture_screenshot": return CaptureScreenshotTool.self
        case "capture_waveform": return CaptureWaveformTool.self
        case "parse_bin_file": return ParseBinFileTool.self
        default: return nil
        }
    }
}

final class MCPServer {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let scope: ScopeConfig?
    private let enabledTools: Set<String>
    private var toolInstances: [String: any MCPTool] = [:]

    init(scope: ScopeConfig?, enabledTools: Set<String> = MCPTools.allNames) {
        self.scope = scope
        self.enabledTools = enabledTools
        self.encoder.outputFormatting = []
        for name in enabledTools {
            if let tool = MCPTools.createTool(name: name, scope: scope) {
                toolInstances[name] = tool
            }
        }
    }

    func run() async {
        while let line = readLine() {
            guard !line.isEmpty else { continue }
            do {
                let request = try decoder.decode(JSONRPCRequest.self, from: Data(line.utf8))
                if let response = await handleRequest(request) {
                    sendResponse(response)
                }
            } catch {
                sendResponse(JSONRPCResponse(id: nil, error: .parseError(error.localizedDescription)))
            }
        }
    }

    private func sendResponse(_ response: JSONRPCResponse) {
        do {
            let data = try encoder.encode(response)
            if let json = String(data: data, encoding: .utf8) {
                print(json)
                fflush(stdout)
            }
        } catch {
            print("{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32603,\"message\":\"Encoding error\"}}")
            fflush(stdout)
        }
    }

    private func handleRequest(_ request: JSONRPCRequest) async -> JSONRPCResponse? {
        if request.id == nil { return nil }
        switch request.method {
        case "initialize": return handleInitialize(request)
        case "tools/list": return handleToolsList(request)
        case "tools/call": return await handleToolsCall(request)
        default:
            return JSONRPCResponse(id: request.id, error: .methodNotFound(request.method))
        }
    }

    private func handleInitialize(_ request: JSONRPCRequest) -> JSONRPCResponse {
        let result: JSONValue = .object([
            "protocolVersion": .string("2024-11-05"),
            "serverInfo": .object([
                "name": .string("ow"),
                "version": .string("2.0.0")
            ]),
            "capabilities": .object([
                "tools": .object([:])
            ])
        ])
        return JSONRPCResponse(id: request.id, result: result)
    }

    private func handleToolsList(_ request: JSONRPCRequest) -> JSONRPCResponse {
        var tools: [JSONValue] = []
        for name in enabledTools.sorted() {
            if let toolType = MCPTools.toolType(name: name) {
                tools.append(toolType.mcpToolDefinition)
            }
        }
        return JSONRPCResponse(id: request.id, result: .object(["tools": .array(tools)]))
    }

    private func handleToolsCall(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        guard let params = request.params?.objectValue,
              let name = params["name"]?.stringValue else {
            return JSONRPCResponse(id: request.id, error: .invalidParams("Missing tool name"))
        }
        guard enabledTools.contains(name), let tool = toolInstances[name] else {
            return JSONRPCResponse(id: request.id, error: .methodNotFound("Unknown tool: \(name)"))
        }
        let args = params["arguments"]?.objectValue ?? [:]
        do {
            let content = try await tool.execute(args: args)
            return JSONRPCResponse(id: request.id, result: .object(["content": .array(content)]))
        } catch {
            return JSONRPCResponse(id: request.id, error: .internalError(error.localizedDescription))
        }
    }
}
