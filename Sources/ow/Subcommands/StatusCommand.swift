import ArgumentParser
import Foundation

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Probe the scope and print its identity and a quick capture summary."
    )

    @OptionGroup var scope: ScopeOptions

    @Flag(name: .long, help: "Skip the waveform capture; only do a TCP-level reachability check.")
    var quick: Bool = false

    mutating func run() async throws {
        let config = try scope.resolve()
        let client = ScopeClient(config)
        print("scope: \(config.host):\(config.port)")
        do {
            try await client.probe()
            print("tcp:   reachable")
        } catch {
            print("tcp:   UNREACHABLE (\(error))")
            throw ExitCode.failure
        }
        if quick { return }
        do {
            let response = try await client.capture(.startWaveform)
            let bin = try BinFile.parse(response.payload)
            print("device: \(bin.deviceIdentifier)\(bin.modelSerial.map { " (\($0))" } ?? "")")
            print("channel: \(bin.channelIdentifier)")
            print("samples: \(bin.samples.count)")
            print("frequency: \(formatFreq(bin.frequency))")
        } catch {
            print("capture: FAILED (\(error))")
            throw ExitCode.failure
        }
    }
}
