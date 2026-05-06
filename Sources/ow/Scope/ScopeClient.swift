import Foundation
import Network

/// Async TCP client for an Owon SDS-series oscilloscope.
///
/// Each capture opens a fresh connection, sends one command, reads until EOF, then closes.
/// The scope drops the connection after streaming the response. Stateless aside from the
/// configuration, so a regular class (not an actor) is sufficient.
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

    /// TCP-level connectivity check. Opens a connection and immediately closes it.
    func probe() async throws {
        let connection = makeConnection()
        try await openConnection(connection)
        connection.cancel()
    }

    // MARK: - Internals

    private func send(_ payload: Data) async throws -> Data {
        let connection = makeConnection()
        log("opening connection")
        try await openConnection(connection)
        log("connection open")
        defer { connection.cancel() }

        try await sendAll(connection, payload: payload)
        log("send complete (\(payload.count) bytes)")
        let data = try await receiveAll(connection)
        log("receive complete (\(data.count) bytes)")
        return data
    }

    private func log(_ message: String) {
        if ProcessInfo.processInfo.environment["OW_DEBUG"] != nil {
            FileHandle.standardError.write(Data("[ow] \(message)\n".utf8))
        }
    }

    private let networkQueue = DispatchQueue(label: "net.bbum.ow.scope")

    private func makeConnection() -> NWConnection {
        let host = NWEndpoint.Host(config.host)
        let port = NWEndpoint.Port(rawValue: config.port)!
        let params = NWParameters.tcp
        return NWConnection(host: host, port: port, using: params)
    }

    private func openConnection(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let resumed = ResumedFlag()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resumed.tryClaim() { cont.resume() }
                case .failed(let err):
                    if resumed.tryClaim() { cont.resume(throwing: ScopeClientError.connectionFailed(err)) }
                case .cancelled:
                    if resumed.tryClaim() { cont.resume(throwing: ScopeClientError.cancelled) }
                default:
                    break
                }
            }
            connection.start(queue: networkQueue)
            networkQueue.asyncAfter(deadline: .now() + config.connectTimeout) {
                if resumed.tryClaim() {
                    connection.cancel()
                    cont.resume(throwing: ScopeClientError.connectTimeout)
                }
            }
        }
    }

    private func sendAll(_ connection: NWConnection, payload: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: payload, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: ScopeClientError.sendFailed(error))
                } else {
                    cont.resume()
                }
            })
        }
    }

    private func receiveAll(_ connection: NWConnection) async throws -> Data {
        var buffer = Data()
        // Idle-timeout: rearm after every chunk. Cancels the connection if the
        // scope goes silent for more than receiveTimeout seconds, which forces
        // any pending receive callback to error out (we treat ECANCELED as EOF).
        let idleTimer = IdleTimer(queue: networkQueue) { connection.cancel() }
        defer { idleTimer.cancel() }
        idleTimer.rearm(after: config.receiveTimeout)
        while true {
            let (chunk, isComplete) = try await receiveOne(connection)
            if let chunk {
                buffer.append(chunk)
                idleTimer.rearm(after: config.receiveTimeout)
            }
            if isComplete {
                log("rx final, total \(buffer.count) bytes")
                return buffer
            }
        }
    }

    private func receiveOne(_ connection: NWConnection) async throws -> (Data?, Bool) {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(Data?, Bool), Error>) in
            // Connection-reset and cancellation are normal terminal states; treat as EOF.
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                if let error {
                    switch error {
                    case .posix(.ECONNRESET), .posix(.ECANCELED):
                        cont.resume(returning: (data, true))
                    default:
                        cont.resume(throwing: ScopeClientError.receiveFailed(error))
                    }
                } else {
                    cont.resume(returning: (data, isComplete))
                }
            }
        }
    }
}

enum ScopeClientError: Error, CustomStringConvertible {
    case connectFailed(Error)
    case connectionFailed(Error)
    case connectTimeout
    case cancelled
    case sendFailed(Error)
    case receiveFailed(Error)
    case receiveTimeout

    var description: String {
        switch self {
        case .connectFailed(let e), .connectionFailed(let e):
            return "connection failed: \(e.localizedDescription)"
        case .connectTimeout:
            return "connection timed out"
        case .cancelled:
            return "connection cancelled"
        case .sendFailed(let e):
            return "send failed: \(e.localizedDescription)"
        case .receiveFailed(let e):
            return "receive failed: \(e.localizedDescription)"
        case .receiveTimeout:
            return "receive timed out"
        }
    }
}

/// Single-shot flag used to ensure a continuation is resumed exactly once.
private final class ResumedFlag: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func tryClaim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

/// A rearmable single-shot timer dispatched to a serial queue.
private final class IdleTimer: @unchecked Sendable {
    private let queue: DispatchQueue
    private let action: () -> Void
    private var workItem: DispatchWorkItem?
    private let lock = NSLock()

    init(queue: DispatchQueue, action: @escaping () -> Void) {
        self.queue = queue
        self.action = action
    }

    func rearm(after seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        workItem?.cancel()
        let item = DispatchWorkItem { [action] in action() }
        workItem = item
        queue.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        workItem?.cancel()
        workItem = nil
    }
}
