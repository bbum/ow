import Foundation

/// Wire commands the SDS7102(V) responds to.
/// Discovered by reverse engineering — the manual documents none of these.
enum WireCommand: String, Sendable {
    case startScreenshot = "STARTBMP"
    case startWaveform = "STARTBIN"
    case startDeepMemory = "STARTMEMDEPTH"

    var bytes: Data { Data((rawValue + "\n").utf8) }
}

/// 12-byte response header that prefixes both BMP and BIN payloads.
struct ResponseEnvelope: Sendable {
    /// Number of bytes that follow the envelope.
    let payloadLength: Int
    /// Unknown second int32. Zero on STARTBIN, nonzero on STARTBMP.
    /// Possibly capture id, checksum, or timestamp.
    let unknown: UInt32
    /// Third int32. STARTBMP=1, STARTBIN/MEMDEPTH=128.
    let flag: UInt32

    static let size = 12

    static func parse(_ data: Data) throws -> ResponseEnvelope {
        var reader = BinaryReader(data)
        let payload = Int(UInt32(bitPattern: try reader.readInt32LE()))
        let unknown = UInt32(bitPattern: try reader.readInt32LE())
        let flag = UInt32(bitPattern: try reader.readInt32LE())
        return ResponseEnvelope(payloadLength: payload, unknown: unknown, flag: flag)
    }
}

/// A capture response from the scope: envelope + payload bytes.
struct CaptureResponse: Sendable {
    let envelope: ResponseEnvelope
    let payload: Data

    /// Parse a raw on-the-wire response (envelope + payload).
    static func parse(_ raw: Data) throws -> CaptureResponse {
        guard raw.count >= ResponseEnvelope.size else {
            throw WireProtocolError.shortResponse(received: raw.count, expected: ResponseEnvelope.size)
        }
        let envelope = try ResponseEnvelope.parse(raw.prefix(ResponseEnvelope.size))
        let payload = raw.suffix(from: raw.startIndex + ResponseEnvelope.size)
        if payload.count != envelope.payloadLength {
            throw WireProtocolError.payloadLengthMismatch(
                declared: envelope.payloadLength,
                actual: payload.count
            )
        }
        return CaptureResponse(envelope: envelope, payload: Data(payload))
    }
}

enum WireProtocolError: Error, CustomStringConvertible {
    case shortResponse(received: Int, expected: Int)
    case payloadLengthMismatch(declared: Int, actual: Int)

    var description: String {
        switch self {
        case .shortResponse(let r, let e):
            return "scope response too short: received \(r) bytes, need at least \(e)"
        case .payloadLengthMismatch(let d, let a):
            return "scope payload length mismatch: envelope declared \(d), got \(a)"
        }
    }
}
