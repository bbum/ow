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

    /// Drain the connection until isComplete (or peer reset). The entire receive
    /// loop runs synchronously inside NWConnection's callback chain on the
    /// network queue — only one continuation hop at the end. Avoids per-chunk
    /// Swift Concurrency overhead, which nc-via-select doesn't pay either.
    private func receiveAll(_ connection: NWConnection) async throws -> Data {
        let log = self.log
        let timeout = config.receiveTimeout
        let queue = networkQueue
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            let state = ReceiveState()
            let idleTimer = IdleTimer(queue: queue) { connection.cancel() }
            idleTimer.rearm(after: timeout)

            func resume(_ result: Result<Data, Error>) {
                guard state.tryFinish() else { return }
                idleTimer.cancel()
                cont.resume(with: result)
            }

            func receiveLoop() {
                // Pick a minimumIncompleteLength that matches what we know:
                //  - Before the envelope is parsed, fetch just enough to see it (12 bytes).
                //  - After parsing, request 64KB at a time to avoid one-callback-per-TCP-
                //    segment overhead, but never more than the bytes still expected
                //    (otherwise the final partial chunk hangs waiting for bytes that
                //    will never arrive — the scope stops sending without sending FIN).
                let minLen: Int
                if state.expectedTotal == 0 {
                    minLen = max(1, ResponseEnvelope.size - state.buffer.count)
                } else {
                    let remaining = max(1, state.expectedTotal - state.buffer.count)
                    minLen = min(64 * 1024, remaining)
                }
                connection.receive(minimumIncompleteLength: minLen, maximumLength: 1024 * 1024) { data, _, isComplete, error in
                    if let data, !data.isEmpty {
                        state.buffer.append(data)
                        idleTimer.rearm(after: timeout)
                    }
                    if let error {
                        switch error {
                        case .posix(.ECONNRESET), .posix(.ECANCELED):
                            log("rx terminal error (peer reset/cancelled), total \(state.buffer.count) bytes")
                            resume(.success(state.buffer))
                        default:
                            resume(.failure(ScopeClientError.receiveFailed(error)))
                        }
                        return
                    }
                    if isComplete {
                        log("rx EOF, total \(state.buffer.count) bytes")
                        resume(.success(state.buffer))
                        return
                    }
                    // The scope stops sending without closing the connection, so
                    // EOF would only arrive on idle timeout (~5s of dead air).
                    // Parse the 12-byte envelope as soon as we have it and stop
                    // receiving once we've got declared payload + envelope.
                    if state.expectedTotal == 0, state.buffer.count >= ResponseEnvelope.size {
                        if let env = try? ResponseEnvelope.parse(state.buffer.prefix(ResponseEnvelope.size)) {
                            state.expectedTotal = ResponseEnvelope.size + env.payloadLength
                            log("envelope: payload=\(env.payloadLength) flag=\(env.flag), expecting \(state.expectedTotal) total")
                        }
                    }
                    if state.expectedTotal > 0, state.buffer.count >= state.expectedTotal {
                        log("rx complete (envelope-driven), total \(state.buffer.count) bytes")
                        resume(.success(state.buffer))
                        return
                    }
                    receiveLoop()
                }
            }
            receiveLoop()
        }
    }
}

/// Mutable state owned by the receive loop. The closure-based loop runs on the
/// network queue (single-threaded) so unsynchronized mutation is safe.
private final class ReceiveState: @unchecked Sendable {
    var buffer = Data()
    /// Total bytes expected (envelope + payload). Set to a positive value once
    /// we've parsed the 12-byte envelope.
    var expectedTotal = 0
    private var finished = false
    func tryFinish() -> Bool {
        if finished { return false }
        finished = true
        return true
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
