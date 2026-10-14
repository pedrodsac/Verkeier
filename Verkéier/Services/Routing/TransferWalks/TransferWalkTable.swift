import CryptoKit
import Foundation

/// An immutable, validated, memory-mappable table of transfer walk outcomes.
/// Lookups binary-search the sorted index and decode only the matching payload.
nonisolated final class TransferWalkTable: Sendable {
    struct Header: Equatable, Sendable {
        let graphIdentity: String
        /// `nil` when the table does not claim coverage of a timetable.
        let timetableIdentity: String?
        let entryCount: Int
    }

    let header: Header
    private let data: Data
    private let indexStart: Int

    var count: Int { header.entryCount }
    var graphIdentity: String { header.graphIdentity }
    var timetableIdentity: String? { header.timetableIdentity }

    /// Validates the whole file: structure, bounds, ordering and the SHA-256 footer.
    init(data: Data) throws {
        let fixed = TransferWalkTableCodec.headerFixedSize
        let footer = TransferWalkTableCodec.footerSize
        guard data.count >= fixed + footer else { throw TransferWalkTableError.malformed("too short") }
        let body = data.count - footer
        let digest = Array(SHA256.hash(data: data.prefix(body)))
        guard digest == Array(data.suffix(footer)) else { throw TransferWalkTableError.malformed("checksum") }
        let parsed = try Self.parseHeader(data, limit: body)
        let count = parsed.header.entryCount
        let (indexBytes, overflow) = count.multipliedReportingOverflow(by: TransferWalkTableCodec.indexEntrySize)
        guard !overflow, parsed.indexStart <= body, indexBytes <= body - parsed.indexStart else {
            throw TransferWalkTableError.malformed("index bounds")
        }
        // Keys strictly increase and payloads are contiguous up to the footer.
        var reader = TransferWalkBinaryReader(data: data, offset: parsed.indexStart, end: body)
        var expectedOffset = parsed.indexStart + indexBytes
        var previous: TransferWalkKey?
        for _ in 0..<count {
            let key = TransferWalkKey(fromLatitudeBits: try reader.readUInt64(), fromLongitudeBits: try reader.readUInt64(),
                                      toLatitudeBits: try reader.readUInt64(), toLongitudeBits: try reader.readUInt64())
            let offset = try reader.readUInt64(), length = try reader.readUInt32()
            _ = try reader.readUInt32()
            if let previous, !(previous < key) { throw TransferWalkTableError.malformed("index order") }
            guard offset == UInt64(expectedOffset), length >= 1 else { throw TransferWalkTableError.malformed("payload range") }
            expectedOffset += Int(length)
            guard expectedOffset <= body else { throw TransferWalkTableError.malformed("payload bounds") }
            previous = key
        }
        guard expectedOffset == body else { throw TransferWalkTableError.malformed("payload tail") }
        self.header = parsed.header
        self.data = data
        self.indexStart = parsed.indexStart
    }

    private static func parseHeader(_ data: Data, limit: Int) throws -> (header: Header, indexStart: Int) {
        var reader = TransferWalkBinaryReader(data: data, end: limit)
        for byte in TransferWalkTableCodec.magic {
            guard try reader.readUInt8() == byte else { throw TransferWalkTableError.malformed("magic") }
        }
        guard try reader.readUInt16() == TransferWalkTableCodec.formatVersion else {
            throw TransferWalkTableError.malformed("version")
        }
        _ = try reader.readUInt16()
        let count = Int(try reader.readUInt32())
        let graphLength = Int(try reader.readUInt32()), timetableLength = Int(try reader.readUInt32())
        let graph = try reader.readUTF8(count: graphLength)
        let timetable = try reader.readUTF8(count: timetableLength)
        return (Header(graphIdentity: graph, timetableIdentity: timetable.isEmpty ? nil : timetable, entryCount: count),
                reader.offset)
    }

    /// Reads only the header of a table file, without hashing or mapping it.
    static func readHeader(at url: URL) -> Header? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: 4_096), prefix.count >= TransferWalkTableCodec.headerFixedSize,
              let parsed = try? parseHeader(prefix, limit: prefix.count) else { return nil }
        return parsed.header
    }

    // MARK: Lookup

    func outcome(for key: TransferWalkKey) -> TransferWalkOutcome? {
        guard let payload = payload(for: key) else { return nil }
        return try? TransferWalkTableCodec.decodePayload(payload)
    }

    /// The stored payload bytes, so an incremental build can reuse them unchanged.
    func payload(for key: TransferWalkKey) -> Data? {
        var low = 0, high = count
        while low < high {
            let middle = low + (high - low) / 2
            guard let entry = entry(at: middle) else { return nil }
            if entry.key == key {
                let start = Int(entry.offset)
                return data.subdata(in: (data.startIndex + start)..<(data.startIndex + start + Int(entry.length)))
            }
            if entry.key < key { low = middle + 1 } else { high = middle }
        }
        return nil
    }

    /// Number of stored deterministic "no route" entries.
    func negativeCount() -> Int {
        (0..<count).reduce(0) { total, index in
            guard let entry = entry(at: index) else { return total }
            return data[data.startIndex + Int(entry.offset)] == 0 ? total + 1 : total
        }
    }

    private func entry(at index: Int) -> (key: TransferWalkKey, offset: UInt64, length: UInt32)? {
        var reader = TransferWalkBinaryReader(data: data, offset: indexStart + index * TransferWalkTableCodec.indexEntrySize)
        guard let a = try? reader.readUInt64(), let b = try? reader.readUInt64(),
              let c = try? reader.readUInt64(), let d = try? reader.readUInt64(),
              let offset = try? reader.readUInt64(), let length = try? reader.readUInt32() else { return nil }
        return (TransferWalkKey(fromLatitudeBits: a, fromLongitudeBits: b, toLatitudeBits: c, toLongitudeBits: d), offset, length)
    }
}
