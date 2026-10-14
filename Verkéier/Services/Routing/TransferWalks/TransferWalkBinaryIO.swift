import Foundation

/// Little-endian encoder for the transfer walk file format.
nonisolated struct TransferWalkBinaryWriter {
    private(set) var data = Data()

    mutating func append(_ value: UInt8) { data.append(value) }
    mutating func append(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
    mutating func append(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
    mutating func append(_ value: UInt64) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
    mutating func append(bits value: Double) { append(value.bitPattern) }
    mutating func append(bytes: Data) { data.append(bytes) }
    mutating func append(utf8 string: String) { data.append(contentsOf: Array(string.utf8)) }
}

/// Bounds-checked reader. Offsets are relative to the start of `data`, which
/// keeps it correct for both memory-mapped files and `Data` slices.
nonisolated struct TransferWalkBinaryReader {
    let data: Data
    private(set) var offset: Int
    let end: Int

    init(data: Data, offset: Int = 0, end: Int? = nil) {
        self.data = data
        self.offset = offset
        self.end = end ?? data.count
    }

    var remaining: Int { end - offset }

    private mutating func take<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        let size = MemoryLayout<T>.size
        guard offset >= 0, size <= remaining, end <= data.count else {
            throw TransferWalkTableError.malformed("read past end")
        }
        let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
        offset += size
        return T(littleEndian: value)
    }

    mutating func readUInt8() throws -> UInt8 { try take(UInt8.self) }
    mutating func readUInt16() throws -> UInt16 { try take(UInt16.self) }
    mutating func readUInt32() throws -> UInt32 { try take(UInt32.self) }
    mutating func readUInt64() throws -> UInt64 { try take(UInt64.self) }
    mutating func readDouble() throws -> Double { Double(bitPattern: try readUInt64()) }

    mutating func readUTF8(count: Int) throws -> String {
        guard count >= 0, count <= remaining else { throw TransferWalkTableError.malformed("string length") }
        let bytes = data.subdata(in: (data.startIndex + offset)..<(data.startIndex + offset + count))
        offset += count
        guard let string = String(validating: bytes, as: UTF8.self) else {
            throw TransferWalkTableError.malformed("invalid UTF-8")
        }
        return string
    }
}
