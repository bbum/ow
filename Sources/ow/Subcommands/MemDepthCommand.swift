import ArgumentParser
import Foundation

struct MemDepthCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "memdepth",
        abstract: "Capture a deep-memory waveform to a .bin file (STARTMEMDEPTH)."
    )

    @OptionGroup var scope: ScopeOptions

    @Argument(help: "Output .bin file path.")
    var output: String

    mutating func run() async throws {
        try await captureToFile(command: .startDeepMemory, output: output, scope: scope)
    }
}
