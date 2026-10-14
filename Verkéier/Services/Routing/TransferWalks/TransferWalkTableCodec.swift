import CryptoKit
import Foundation

/// Deterministic encoding of transfer walk payloads and tables. All doubles
/// are stored as raw bit patterns, so a decoded value is bit-identical.
nonisolated enum TransferWalkTableCodec {
    static let magic: [UInt8] = Array("VKTW".utf8)
    static let formatVersion: UInt16 = 1
    static let headerFixedSize = 20
    static let indexEntrySize = 48
    static let footerSize = 32

    // MARK: Payload

    static func encodePayload(_ outcome: TransferWalkOutcome) throws -> Data {
        var writer = TransferWalkBinaryWriter()
        switch outcome {
        case .noRoute:
            writer.append(UInt8(0))
        case .route(let route):
            // Station connections carry names that depend on the request; they
            // are never stored in format v1.
            guard route.segments.isEmpty else { throw TransferWalkTableError.unsupported("segments") }
            writer.append(UInt8(1))
            writer.append(bits: route.distanceMeters)
            writer.append(bits: route.duration)
            writer.append(Self.code(for: route.source))
            writer.append(UInt32(route.coordinates.count))
            for coordinate in route.coordinates {
                writer.append(bits: coordinate.latitude)
                writer.append(bits: coordinate.longitude)
            }
            writer.append(UInt32(0))
        }
        return writer.data
    }

    static func decodePayload(_ data: Data) throws -> TransferWalkOutcome {
        var reader = TransferWalkBinaryReader(data: data)
        switch try reader.readUInt8() {
        case 0:
            guard reader.remaining == 0 else { throw TransferWalkTableError.malformed("trailing bytes") }
            return .noRoute
        case 1:
            let distance = try reader.readDouble()
            let duration = try reader.readDouble()
            let source = try Self.source(for: try reader.readUInt8())
            let count = Int(try reader.readUInt32())
            guard count >= 0, count <= reader.remaining / 16 else {
                throw TransferWalkTableError.malformed("coordinate count")
            }
            var coordinates: [RouteMapCoordinate] = []
            coordinates.reserveCapacity(count)
            for _ in 0..<count {
                let latitude = try reader.readDouble()
                coordinates.append(RouteMapCoordinate(latitude: latitude, longitude: try reader.readDouble()))
            }
            guard try reader.readUInt32() == 0 else { throw TransferWalkTableError.unsupported("segments") }
            guard reader.remaining == 0 else { throw TransferWalkTableError.malformed("trailing bytes") }
            return .route(
                OfflineWalkingRoute(
                    distanceMeters: distance,
                    duration: duration,
                    coordinates: coordinates,
                    source: source
                )
            )
        default:
            throw TransferWalkTableError.malformed("payload kind")
        }
    }

    private static func code(for source: WalkingEstimateSource) -> UInt8 {
        switch source {
        case .localOSM: 1
        case .stationConnection: 2
        case .mapKit: 3
        case .straightLineEstimate: 4
        }
    }

    private static func source(for code: UInt8) throws -> WalkingEstimateSource {
        switch code {
        case 1: .localOSM
        case 2: .stationConnection
        case 3: .mapKit
        case 4: .straightLineEstimate
        default: throw TransferWalkTableError.malformed("source code")
        }
    }

    // MARK: Table

    /// `entries` must be strictly increasing by key. The same entries always
    /// produce the same bytes, so an incremental build equals a full build.
    static func encodeTable(
        graphIdentity: String,
        timetableIdentity: String?,
        entries: [(key: TransferWalkKey, payload: Data)]
    ) throws -> Data {
        for index in entries.indices.dropFirst() where !(entries[index - 1].key < entries[index].key) {
            throw TransferWalkTableError.malformed("entries not strictly increasing")
        }
        let timetable = timetableIdentity ?? ""
        let graphBytes = Array(graphIdentity.utf8), timetableBytes = Array(timetable.utf8)
        let payloadStart = headerFixedSize + graphBytes.count + timetableBytes.count + entries.count * indexEntrySize
        var writer = TransferWalkBinaryWriter()
        for byte in magic { writer.append(byte) }
        writer.append(formatVersion)
        writer.append(UInt16(0))
        writer.append(UInt32(entries.count))
        writer.append(UInt32(graphBytes.count))
        writer.append(UInt32(timetableBytes.count))
        writer.append(utf8: graphIdentity)
        writer.append(utf8: timetable)
        var offset = payloadStart
        for entry in entries {
            writer.append(entry.key.fromLatitudeBits)
            writer.append(entry.key.fromLongitudeBits)
            writer.append(entry.key.toLatitudeBits)
            writer.append(entry.key.toLongitudeBits)
            writer.append(UInt64(offset))
            writer.append(UInt32(entry.payload.count))
            writer.append(UInt32(0))
            offset += entry.payload.count
        }
        for entry in entries { writer.append(bytes: entry.payload) }
        var data = writer.data
        data.append(contentsOf: Array(SHA256.hash(data: data)))
        return data
    }
}
