import Foundation

struct CaptureWaveformTool: MCPTool {
    static let name = "capture_waveform"

    static let description = """
        Capture a waveform from the scope and return the parsed result as JSON. Set
        deep_memory=true to use STARTMEMDEPTH for a longer sample record. By default,
        sample arrays are returned as summary statistics only (min/max/mean/Vpp); set
        include_samples=true to get every sample (potentially large), or
        decimate=N to return every Nth sample.

        Use this to: measure a signal, capture a transient for analysis, decode a
        protocol, or feed sample data into an analysis pipeline.
        """

    static let inputSchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object(scopeOverrideProperties.merging([
            "deep_memory": .object([
                "type": .string("boolean"),
                "description": .string("Use STARTMEMDEPTH for a deep-memory capture (longer sample record).")
            ]),
            "save_path": .object([
                "type": .string("string"),
                "description": .string("Optional path to save the raw .bin file alongside the JSON response.")
            ]),
            "include_samples": .object([
                "type": .string("boolean"),
                "description": .string("Return every sample as a numeric array (default false). Can be very large.")
            ]),
            "decimate": .object([
                "type": .string("integer"),
                "description": .string("Return every Nth sample. Mutually exclusive with include_samples.")
            ])
        ]) { _, new in new })
    ])

    let scope: ScopeConfig

    init(scope: ScopeConfig) {
        self.scope = scope
    }

    func execute(args: [String: JSONValue]) async throws -> [JSONValue] {
        let config = resolveScope(args: args, default: scope)
        let deep = args["deep_memory"]?.boolValue ?? false
        let command: WireCommand = deep ? .startDeepMemory : .startWaveform

        let client = ScopeClient(config)
        let response = try await client.capture(command)

        if let savePath = args["save_path"]?.stringValue {
            let url = URL(fileURLWithPath: (savePath as NSString).expandingTildeInPath)
            try response.payload.write(to: url)
        }

        let bin = try BinFile.parse(response.payload)
        let json = waveformJSON(bin: bin, args: args)
        let pretty = try JSONEncoder.prettyEncoded(json)
        return [textBlock(pretty)]
    }
}

func waveformJSON(bin: BinFile, args: [String: JSONValue]) -> JSONValue {
    var fields: [String: JSONValue] = [
        "format": .string(bin.format.rawValue),
        "device": .string(bin.deviceIdentifier),
        "channel": .string(bin.channelIdentifier),
        "frequency_hz": .double(Double(bin.frequency)),
        "period_units": .double(Double(bin.period)),
        "time_multiplier": .double(Double(bin.timeMultiplier)),
        "time_divisor": .int(Int(bin.timeDivisor)),
        "volts_multiplier": .double(Double(bin.voltsMultiplier)),
        "volts_divisor": .int(Int(bin.voltsDivisor)),
        "zero_point": .int(Int(bin.zeroPoint)),
        "attenuation": .int(Int(bin.attenuation)),
        "deep_memory_capture": .bool(bin.deepMemoryCapture),
        "deep_memory_capable": .bool(bin.deepMemoryCapable),
        "sample_count": .int(bin.samples.count),
    ]
    if let modelSerial = bin.modelSerial {
        fields["model_serial"] = .string(modelSerial)
    }

    if !bin.samples.isEmpty {
        let voltages = bin.voltages
        let mn = voltages.min() ?? 0
        let mx = voltages.max() ?? 0
        let mean = voltages.reduce(0, +) / Double(voltages.count)
        fields["voltage_summary"] = .object([
            "min_v": .double(mn),
            "max_v": .double(mx),
            "mean_v": .double(mean),
            "vpp_v": .double(mx - mn),
        ])
    }

    let includeSamples = args["include_samples"]?.boolValue ?? false
    let decimate = args["decimate"]?.intValue ?? 0
    if includeSamples {
        fields["samples"] = .array(bin.samples.map { .int(Int($0)) })
        fields["voltages_v"] = .array(bin.voltages.map { .double($0) })
    } else if decimate > 1 {
        let stride = decimate
        let decimated = (0 ..< bin.samples.count).filter { $0 % stride == 0 }
        fields["samples_decimated"] = .array(decimated.map { .int(Int(bin.samples[$0])) })
        fields["voltages_decimated_v"] = .array(decimated.map { .double(bin.voltage(at: $0)) })
        fields["decimation_stride"] = .int(stride)
    }

    return .object(fields)
}

extension JSONEncoder {
    static func prettyEncoded(_ value: JSONValue) throws -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}
