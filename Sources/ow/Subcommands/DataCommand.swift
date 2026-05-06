import ArgumentParser
import Foundation

struct DataCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "data",
        abstract: "Capture a single waveform to a .bin file (STARTBIN)."
    )

    @OptionGroup var scope: ScopeOptions

    @Argument(help: "Output .bin file path.")
    var output: String

    mutating func run() async throws {
        try await captureToFile(command: .startWaveform, output: output, scope: scope)
    }
}

func captureToFile(command: WireCommand, output: String, scope: ScopeOptions) async throws {
    let config = try scope.resolve()
    let client = ScopeClient(config)
    let response = try await client.capture(command)
    let url = URL(fileURLWithPath: (output as NSString).expandingTildeInPath)
    try response.payload.write(to: url)

    let summary: String
    if let bin = try? BinFile.parse(response.payload) {
        summary = " (\(bin.channelIdentifier), \(bin.samples.count) samples, \(formatFreq(bin.frequency)))"
    } else {
        summary = ""
    }
    FileHandle.standardError.write(Data("wrote \(response.payload.count) bytes to \(url.path)\(summary)\n".utf8))
}

func formatFreq(_ hz: Float) -> String {
    let v = Double(hz)
    if v >= 1_000_000 { return String(format: "%.3f MHz", v / 1_000_000) }
    if v >= 1_000 { return String(format: "%.3f kHz", v / 1_000) }
    return String(format: "%.1f Hz", v)
}
