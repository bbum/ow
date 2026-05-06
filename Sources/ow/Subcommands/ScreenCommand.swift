import ArgumentParser
import Foundation

struct ScreenCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "screen",
        abstract: "Capture the scope display to a BMP (or PNG) file."
    )

    @OptionGroup var scope: ScopeOptions

    @Argument(help: "Output file path. .png extension converts BMP to PNG.")
    var output: String

    mutating func run() async throws {
        let config = try scope.resolve()
        let client = ScopeClient(config)
        let response = try await client.capture(.startScreenshot)
        let url = URL(fileURLWithPath: (output as NSString).expandingTildeInPath)
        let data: Data
        if url.pathExtension.lowercased() == "png" {
            data = try BMP.toPNG(response.payload)
        } else {
            data = response.payload
        }
        try data.write(to: url)
        FileHandle.standardError.write(Data("wrote \(data.count) bytes to \(url.path)\n".utf8))
    }
}
