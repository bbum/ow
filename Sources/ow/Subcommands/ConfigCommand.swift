import ArgumentParser
import Foundation

struct ConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Read or write persisted scope settings (net.bbum.ow defaults).",
        subcommands: [Get.self, Set.self]
    )

    struct Get: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print the persisted host and port."
        )
        mutating func run() async throws {
            let (host, port) = ScopeDefaults.load()
            print("host: \(host ?? "<unset>")")
            print("port: \(port.map(String.init) ?? "<unset>")")
        }
    }

    struct Set: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Persist a host or port. Example: ow config set host 10.0.1.230"
        )
        @Argument(help: "Setting name: host or port.")
        var key: String
        @Argument(help: "Value to write.")
        var value: String

        mutating func run() async throws {
            switch key.lowercased() {
            case "host":
                ScopeDefaults.save(host: value, port: nil)
            case "port":
                guard let p = UInt16(value) else {
                    FileHandle.standardError.write(Data("invalid port: \(value)\n".utf8))
                    throw ExitCode.failure
                }
                ScopeDefaults.save(host: nil, port: p)
            default:
                FileHandle.standardError.write(Data("unknown key: \(key) (expected host or port)\n".utf8))
                throw ExitCode.failure
            }
        }
    }
}
