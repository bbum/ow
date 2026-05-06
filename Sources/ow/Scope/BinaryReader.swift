import Foundation

struct BinaryReader {
    let data: Data
    private(set) var cursor: Int

    init(_ data: Data, cursor: Int = 0) {
        self.data = data
        self.cursor = cursor
    }

    var remaining: Int { data.count - cursor }

    mutating func readASCII(length: Int) throws -> String {
        try ensure(length)
        let slice = data[cursor ..< cursor + length]
        cursor += length
        return String(decoding: slice, as: UTF8.self)
    }

    mutating func readUInt8() throws -> UInt8 {
        try ensure(1)
        let v = data[cursor]
        cursor += 1
        return v
    }

    mutating func readInt32LE() throws -> Int32 {
        try ensure(4)
        let v = data.withUnsafeBytes { buf -> UInt32 in
            let base = buf.baseAddress!.advanced(by: cursor)
            return UInt32(base.load(fromByteOffset: 0, as: UInt8.self))
                 | (UInt32(base.load(fromByteOffset: 1, as: UInt8.self)) << 8)
                 | (UInt32(base.load(fromByteOffset: 2, as: UInt8.self)) << 16)
                 | (UInt32(base.load(fromByteOffset: 3, as: UInt8.self)) << 24)
        }
        cursor += 4
        return Int32(bitPattern: v)
    }

    mutating func readFloat32LE() throws -> Float {
        let bits = UInt32(bitPattern: try readInt32LE())
        return Float(bitPattern: bits)
    }

    mutating func readInt16ArrayLE(count: Int) throws -> [Int16] {
        let byteCount = count * MemoryLayout<Int16>.size
        try ensure(byteCount)
        var out = [Int16](repeating: 0, count: count)
        out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                dst.copyBytes(from: UnsafeRawBufferPointer(rebasing: src[cursor ..< cursor + byteCount]))
            }
        }
        cursor += byteCount
        return out
    }

    mutating func skip(_ n: Int) throws {
        try ensure(n)
        cursor += n
    }

    func peekASCII(at offset: Int, length: Int) -> String? {
        let start = cursor + offset
        guard start + length <= data.count else { return nil }
        return String(decoding: data[start ..< start + length], as: UTF8.self)
    }

    private func ensure(_ n: Int) throws {
        if remaining < n {
            throw BinaryReaderError.unexpectedEndOfData(needed: n, available: remaining, at: cursor)
        }
    }
}

enum BinaryReaderError: Error, CustomStringConvertible {
    case unexpectedEndOfData(needed: Int, available: Int, at: Int)

    var description: String {
        switch self {
        case .unexpectedEndOfData(let needed, let available, let at):
            return "unexpected end of data at offset \(at): needed \(needed) bytes, only \(available) available"
        }
    }
}
