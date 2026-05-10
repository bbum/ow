import Foundation

struct ScopeStatusTool: MCPTool {
    static let name = "scope_status"

    static let description = """
        Probe the oscilloscope. Verifies TCP reachability and (if reachable) returns the device
        identifier, model, serial, current channel, and detected frequency. Use this to
        confirm the scope is online before issuing capture commands.
        """

    static let inputSchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object(scopeOverrideProperties.merging([
            "quick": .object([
                "type": .string("boolean"),
                "description": .string("Skip the waveform-based identification capture and only do a TCP probe.")
            ])
        ]) { _, new in new })
    ])

    let scope: ScopeConfig?

    init(scope: ScopeConfig?) {
        self.scope = scope
    }

    func execute(args: [String: JSONValue]) async throws -> [JSONValue] {
        guard let config = resolveScope(args: args, default: scope) else { return [noHostBlock] }
        let client = ScopeClient(config)
        do {
            try await client.probe()
        } catch {
            return [textBlock("scope: \(config.host):\(config.port)\ntcp: UNREACHABLE (\(error))")]
        }
        let quick = args["quick"]?.boolValue ?? false
        if quick {
            return [textBlock("scope: \(config.host):\(config.port)\ntcp: reachable")]
        }
        do {
            let response = try await client.capture(.startWaveform)
            let bin = try BinFile.parse(response.payload)
            var lines: [String] = []
            lines.append("scope: \(config.host):\(config.port)")
            lines.append("tcp: reachable")
            lines.append("device: \(bin.deviceIdentifier)")
            if let modelSerial = bin.modelSerial {
                lines.append("model+serial: \(modelSerial)")
            }
            lines.append("channel: \(bin.channelIdentifier)")
            lines.append("samples: \(bin.samples.count)")
            lines.append("frequency: \(formatFreq(bin.frequency))")
            lines.append("deep memory capable: \(bin.deepMemoryCapable)")
            return [textBlock(lines.joined(separator: "\n"))]
        } catch {
            return [textBlock("scope: \(config.host):\(config.port)\ntcp: reachable\ncapture: FAILED (\(error))")]
        }
    }
}

func textBlock(_ s: String) -> JSONValue {
    .object([
        "type": .string("text"),
        "text": .string(s)
    ])
}
