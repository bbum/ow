import Foundation

/// Decoded Owon scope `.bin` capture file.
///
/// Handles both the **live network format** (returned by STARTBIN / STARTMEMDEPTH —
/// includes a metadata preamble with model + serial) and the **USB-saved format**
/// (the simpler legacy layout where `CH<n>` follows immediately after `fileLength`).
///
/// See PROTOCOL.md for the full byte-level reference.
struct BinFile: Sendable {
    let format: BinFormat
    let deviceIdentifier: String
    /// Model + serial, only present in live network captures (e.g. "SDS7102125102").
    let modelSerial: String?
    let channelIdentifier: String

    /// Negative when the capture is "extended" (sets `extendedFlags`).
    /// Absolute value is the nominal sample-data byte count, but is unreliable —
    /// trust `samples.count * 2` instead.
    let blockLength: Int32
    let extendedFlags: Int32?
    let blockOffset: Int32?

    let collectionPoint: Int32
    let collectionPointCount: Int32
    let slowScanningRange: Int32
    let timeDivisor: Int32
    let zeroPoint: Int32
    let voltsDivisor: Int32
    let attenuation: Int32

    let timeMultiplier: Float
    /// Hz — verified to match the scope's measured frequency display.
    let frequency: Float
    let period: Float
    let voltsMultiplier: Float

    /// Raw int16 samples as captured.
    let samples: [Int16]

    var deepMemoryCapture: Bool { (extendedFlags ?? 0) & 0b01 != 0 }
    var deepMemoryCapable: Bool { (extendedFlags ?? 0) & 0b10 != 0 }

    /// Best-effort voltage at sample index. The scaling formula is reverse-engineered;
    /// see PROTOCOL.md for caveats. Live SDS7102 captures match Vpp display when
    /// `voltsMultiplier` is treated as mV/count.
    func voltage(at index: Int) -> Double {
        let raw = Double(samples[index] - Int16(zeroPoint))
        return raw * Double(voltsMultiplier) / 1000.0
    }

    /// Best-effort time at sample index in seconds, treating `timeMultiplier` as µs/sample.
    func time(at index: Int) -> Double {
        Double(index) * Double(timeMultiplier) * 1e-6
    }

    var voltages: [Double] {
        (0 ..< samples.count).map { voltage(at: $0) }
    }
}

enum BinFormat: String, Sendable {
    /// STARTBIN / STARTMEMDEPTH response — has model+serial preamble between deviceID and CH<n>.
    case liveNetwork
    /// Saved-to-USB format — CH<n> follows immediately after the int32 fileLength field.
    case usbSaved
}

enum BinFileError: Error, CustomStringConvertible {
    case missingChannelMarker
    case unexpectedDeviceIdentifier(String)

    var description: String {
        switch self {
        case .missingChannelMarker:
            return "could not locate CH<n> marker in capture body"
        case .unexpectedDeviceIdentifier(let id):
            return "unexpected device identifier: '\(id)'"
        }
    }
}

extension BinFile {
    /// Parse a capture body. Pass the bytes *after* the 12-byte response envelope
    /// has been stripped (or pass a USB-saved file's contents directly — they have
    /// no envelope).
    static func parse(_ data: Data) throws -> BinFile {
        var reader = BinaryReader(data)
        let deviceIdentifier = try reader.readASCII(length: 6)

        let format = try detectFormat(deviceIdentifier: deviceIdentifier, reader: reader)
        let modelSerial: String?

        switch format {
        case .usbSaved:
            // Legacy: 4-byte fileLength field (often a sentinel). Skip it.
            _ = try reader.readInt32LE()
            modelSerial = nil

        case .liveNetwork:
            // Skip the preamble up to (but not including) "CH<n>". Capture model+serial along the way.
            let (preamble, distance) = try scanToChannelMarker(reader: reader)
            modelSerial = extractModelSerial(from: preamble)
            try reader.skip(distance)
        }

        let channelIdentifier = try reader.readASCII(length: 3)
        let blockLength = try reader.readInt32LE()

        let extendedFlags: Int32?
        if blockLength < 0 {
            extendedFlags = try reader.readInt32LE()
        } else {
            extendedFlags = nil
        }

        let blockOffset: Int32?
        if deviceIdentifier.hasPrefix("SPBS") {
            blockOffset = try reader.readInt32LE()
        } else {
            blockOffset = nil
        }

        let collectionPoint = try reader.readInt32LE()
        let collectionPointCount = try reader.readInt32LE()
        let slowScanningRange = try reader.readInt32LE()
        let timeDivisor = try reader.readInt32LE()
        let zeroPoint = try reader.readInt32LE()
        let voltsDivisor = try reader.readInt32LE()
        let attenuation = try reader.readInt32LE()

        let timeMultiplier = try reader.readFloat32LE()
        let frequency = try reader.readFloat32LE()
        let period = try reader.readFloat32LE()
        let voltsMultiplier = try reader.readFloat32LE()

        // Sample count: trust collectionPointCount if it matches the remaining body,
        // else fall back to whatever bytes are left.
        let remainingSampleBytes = reader.remaining
        let declaredSampleCount = Int(collectionPointCount)
        let actualSampleCount: Int
        if declaredSampleCount > 0 && declaredSampleCount * 2 == remainingSampleBytes {
            actualSampleCount = declaredSampleCount
        } else {
            actualSampleCount = remainingSampleBytes / 2
        }
        let samples = try reader.readInt16ArrayLE(count: actualSampleCount)

        return BinFile(
            format: format,
            deviceIdentifier: deviceIdentifier,
            modelSerial: modelSerial,
            channelIdentifier: channelIdentifier,
            blockLength: blockLength,
            extendedFlags: extendedFlags,
            blockOffset: blockOffset,
            collectionPoint: collectionPoint,
            collectionPointCount: collectionPointCount,
            slowScanningRange: slowScanningRange,
            timeDivisor: timeDivisor,
            zeroPoint: zeroPoint,
            voltsDivisor: voltsDivisor,
            attenuation: attenuation,
            timeMultiplier: timeMultiplier,
            frequency: frequency,
            period: period,
            voltsMultiplier: voltsMultiplier,
            samples: samples
        )
    }

    /// Format detection: peek at the bytes immediately following the 6-byte deviceID.
    /// USB-saved captures have a 4-byte int32 (often `0x00FFFFFF`) followed *immediately*
    /// by ASCII `CH<n>`. Live network captures have a longer preamble before `CH<n>`.
    private static func detectFormat(deviceIdentifier: String, reader: BinaryReader) throws -> BinFormat {
        // USB-saved: bytes at +4..+6 from cursor are "CH<digit>"
        if reader.remaining >= 7,
           let channelGuess = reader.peekASCII(at: 4, length: 3),
           channelGuess.hasPrefix("CH"),
           channelGuess.last.map({ $0.isNumber }) == true {
            return .usbSaved
        }
        return .liveNetwork
    }

    /// Scan ahead from the current cursor for the first occurrence of `CH<digit>`.
    /// Returns the bytes scanned over (preamble) and the cursor distance.
    private static func scanToChannelMarker(reader: BinaryReader) throws -> (preamble: Data, distance: Int) {
        let bytes = reader.data
        let start = reader.cursor
        var i = start
        // Reasonable upper bound: 256 bytes of preamble is a lot.
        let limit = min(bytes.count - 3, start + 256)
        while i <= limit {
            if bytes[i] == 0x43,            // 'C'
               bytes[i + 1] == 0x48,        // 'H'
               (0x30...0x39).contains(bytes[i + 2]) { // 0-9
                return (preamble: bytes[start ..< i], distance: i - start)
            }
            i += 1
        }
        throw BinFileError.missingChannelMarker
    }

    /// Pull out model+serial from the live-format preamble (e.g. "SDS7102125102").
    /// Owon SDS-series uses a fixed 7-char model code (SDS + 4 digits) followed by
    /// a 6-char numeric serial = 13 chars total. Anchor on the SDS prefix.
    private static func extractModelSerial(from preamble: Data) -> String? {
        let bytes = Array(preamble)
        let prefix: [UInt8] = [0x53, 0x44, 0x53] // "SDS"
        guard let start = bytes.firstRange(of: prefix)?.lowerBound else { return nil }
        let end = min(start + 13, bytes.count)
        return String(decoding: bytes[start ..< end], as: UTF8.self)
    }
}
