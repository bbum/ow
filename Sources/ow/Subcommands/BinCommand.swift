import ArgumentParser
import Foundation

struct BinCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bin",
        abstract: "Parse and summarize an Owon .bin file. Optionally export to CSV."
    )

    @Flag(name: .long, help: "Write a .csv next to each input with time,voltage columns.")
    var csv: Bool = false

    @Argument(help: "One or more .bin files (or directories containing .bin files).")
    var inputs: [String]

    mutating func run() async throws {
        let files = expand(inputs: inputs)
        guard !files.isEmpty else {
            FileHandle.standardError.write(Data("no .bin files found\n".utf8))
            throw ExitCode.failure
        }
        for url in files {
            let data = try Data(contentsOf: url)
            let bin = try BinFile.parse(data)
            print(format(bin: bin, source: url))
            if csv {
                let csvURL = url.deletingPathExtension().appendingPathExtension("csv")
                try writeCSV(bin: bin, to: csvURL)
                FileHandle.standardError.write(Data("wrote \(csvURL.path)\n".utf8))
            }
        }
    }

    private func expand(inputs: [String]) -> [URL] {
        var out: [URL] = []
        let fm = FileManager.default
        for input in inputs {
            let url = URL(fileURLWithPath: (input as NSString).expandingTildeInPath)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let contents = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                out.append(contentsOf: contents.filter { $0.pathExtension.lowercased() == "bin" })
            } else if url.pathExtension.lowercased() == "bin" {
                out.append(url)
            }
        }
        return out
    }

    private func format(bin: BinFile, source: URL) -> String {
        var lines: [String] = []
        lines.append("\(source.lastPathComponent):")
        lines.append("  format            \(bin.format.rawValue)")
        lines.append("  device            \(bin.deviceIdentifier)")
        if let modelSerial = bin.modelSerial {
            lines.append("  model+serial      \(modelSerial)")
        }
        lines.append("  channel           \(bin.channelIdentifier)")
        lines.append("  samples           \(bin.samples.count)")
        lines.append("  frequency         \(formatFreq(bin.frequency))")
        lines.append("  voltsMultiplier   \(bin.voltsMultiplier)")
        lines.append("  voltsDivisor      \(bin.voltsDivisor)")
        lines.append("  zeroPoint         \(bin.zeroPoint)")
        lines.append("  attenuation       \(bin.attenuation)")
        lines.append("  timeMultiplier    \(bin.timeMultiplier)")
        lines.append("  timeDivisor       \(bin.timeDivisor)")
        lines.append("  deep capture      \(bin.deepMemoryCapture)")
        lines.append("  deep capable      \(bin.deepMemoryCapable)")
        if !bin.samples.isEmpty {
            let mn = bin.samples.min() ?? 0
            let mx = bin.samples.max() ?? 0
            let vmn = bin.voltage(at: bin.samples.firstIndex(of: mn) ?? 0)
            let vmx = bin.voltage(at: bin.samples.firstIndex(of: mx) ?? 0)
            lines.append("  sample range      \(mn) … \(mx)  (≈ \(String(format: "%.3f", vmn)) V … \(String(format: "%.3f", vmx)) V)")
        }
        return lines.joined(separator: "\n")
    }

    private func writeCSV(bin: BinFile, to url: URL) throws {
        var out = "time_s,voltage_v,sample_raw\n"
        for i in 0 ..< bin.samples.count {
            out.append("\(bin.time(at: i)),\(bin.voltage(at: i)),\(bin.samples[i])\n")
        }
        try out.write(to: url, atomically: true, encoding: .utf8)
    }
}
