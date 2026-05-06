import Foundation

/// Async TCP client for an Owon SDS-series oscilloscope.
///
/// Each capture spawns `/usr/bin/nc` to do the actual TCP, sends one command,
/// reads the response, then exits. Stateless aside from configuration, so a
/// regular class (not an actor) is sufficient.
///
/// **Why nc instead of NWConnection or BSD sockets?** Apple's `/usr/bin/nc`
/// holds the private entitlement `com.apple.private.network.intcoproc.restricted.development`,
/// which third-party binaries cannot get. On a multi-homed Mac where one
/// interface has a stale-incomplete ARP for the destination, NWConnection
/// (and even raw `connect()` from a third-party compiled binary) sit in
/// `.waiting` / return `EHOSTUNREACH` instead of using the kernel routing
/// table's choice. `nc` always works because the entitlement bypasses that
/// path-validation layer. Shelling out is ugly but is the only thing that
/// works reliably across multi-homed Macs without requiring the user to
/// disable WiFi or change network topology.
final class ScopeClient: Sendable {
    let config: ScopeConfig

    init(_ config: ScopeConfig) {
        self.config = config
    }

    /// Send a wire command and return the raw response (envelope + payload).
    func capture(_ command: WireCommand) async throws -> CaptureResponse {
        let raw = try await send(command.bytes)
        return try CaptureResponse.parse(raw)
    }

    /// TCP-level connectivity check via `nc -z`. Exit code 0 means the port
    /// answered SYN; non-zero means timeout or RST.
    func probe() async throws {
        try await runOnIOQueue { [config] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: Self.ncPath)
            process.arguments = [
                "-z",
                "-G", String(Int(max(1, config.connectTimeout))),
                "-w", "1",
                config.host, String(config.port)
            ]
            // Suppress nc's "Connection succeeded" message (it goes to stderr).
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                throw ScopeClientError.transportFailed("could not exec nc: \(error.localizedDescription)")
            }
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                throw ScopeClientError.unreachable
            }
        }
    }

    // MARK: - Internals

    /// Use Apple's nc — see comment at top of file. We hard-code the path
    /// because nc earlier on `$PATH` (e.g. a homebrew gnu netcat) would lack
    /// the private entitlement and fail with `EHOSTUNREACH` on multi-homed Macs.
    private static let ncPath = "/usr/bin/nc"

    private func send(_ payload: Data) async throws -> Data {
        try await runOnIOQueue { [config] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: Self.ncPath)
            // -G: connect timeout (seconds). -w: idle timeout — how long to
            // wait for more data after the scope goes silent. The scope sends
            // its envelope+body and then stops without closing, so we rely on
            // -w to terminate the read.
            process.arguments = [
                "-G", String(Int(max(1, config.connectTimeout))),
                "-w", String(Int(max(1, config.receiveTimeout))),
                config.host, String(config.port)
            ]
            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            Self.log("spawning nc \(process.arguments?.joined(separator: " ") ?? "") (\(payload.count) byte cmd)")
            do {
                try process.run()
            } catch {
                throw ScopeClientError.transportFailed("could not exec nc: \(error.localizedDescription)")
            }

            // Send the command and signal EOF on our write end. nc forwards
            // the bytes to the socket, then waits for response.
            do {
                try stdinPipe.fileHandleForWriting.write(contentsOf: payload)
                try stdinPipe.fileHandleForWriting.close()
            } catch {
                process.terminate()
                throw ScopeClientError.transportFailed("write to nc stdin failed: \(error.localizedDescription)")
            }

            // Drain stdout fully. With BMPs this reaches ~1.4 MB.
            let data: Data
            do {
                data = try stdoutPipe.fileHandleForReading.readToEnd() ?? Data()
            } catch {
                process.terminate()
                throw ScopeClientError.transportFailed("read from nc stdout failed: \(error.localizedDescription)")
            }

            process.waitUntilExit()
            let status = process.terminationStatus
            Self.log("nc exited status=\(status), \(data.count) bytes")

            if data.isEmpty {
                // nc returned no bytes. Capture stderr to surface why
                // (e.g. "Connection refused", "Operation timed out").
                let err = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? nil
                let msg = err.flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines)
                if status != 0 {
                    throw ScopeClientError.unreachable
                }
                throw ScopeClientError.transportFailed("nc returned no data\(msg.map { ": \($0)" } ?? "")")
            }

            return data
        }
    }

    private static let ioQueue = DispatchQueue(label: "net.bbum.ow.scope.io", qos: .userInitiated)

    private func runOnIOQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
            Self.ioQueue.async {
                do { cont.resume(returning: try work()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    fileprivate static func log(_ message: String) {
        if ProcessInfo.processInfo.environment["OW_DEBUG"] != nil {
            FileHandle.standardError.write(Data("[ow] \(message)\n".utf8))
        }
    }
}

enum ScopeClientError: Error, CustomStringConvertible {
    case unreachable
    case transportFailed(String)

    var description: String {
        switch self {
        case .unreachable:
            return "scope unreachable (TCP probe failed)"
        case .transportFailed(let s):
            return s
        }
    }
}
