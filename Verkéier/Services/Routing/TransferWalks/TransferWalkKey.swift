import Foundation

/// A directed stop-to-stop pair, keyed by the exact bit patterns of its four
/// coordinates. Two coordinates that differ in the last bit are different pairs,
/// exactly as in `MeasuredWalkingRouteCache`.
nonisolated struct TransferWalkKey: Hashable, Comparable, Sendable {
    let fromLatitudeBits: UInt64
    let fromLongitudeBits: UInt64
    let toLatitudeBits: UInt64
    let toLongitudeBits: UInt64

    init(fromLatitudeBits: UInt64, fromLongitudeBits: UInt64, toLatitudeBits: UInt64, toLongitudeBits: UInt64) {
        self.fromLatitudeBits = fromLatitudeBits
        self.fromLongitudeBits = fromLongitudeBits
        self.toLatitudeBits = toLatitudeBits
        self.toLongitudeBits = toLongitudeBits
    }

    init(from: LocationPoint, to: LocationPoint) {
        self.init(
            fromLatitudeBits: from.latitude.bitPattern,
            fromLongitudeBits: from.longitude.bitPattern,
            toLatitudeBits: to.latitude.bitPattern,
            toLongitudeBits: to.longitude.bitPattern
        )
    }

    /// One comparator serves sorting on write and binary search on read.
    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.fromLatitudeBits != rhs.fromLatitudeBits { return lhs.fromLatitudeBits < rhs.fromLatitudeBits }
        if lhs.fromLongitudeBits != rhs.fromLongitudeBits { return lhs.fromLongitudeBits < rhs.fromLongitudeBits }
        if lhs.toLatitudeBits != rhs.toLatitudeBits { return lhs.toLatitudeBits < rhs.toLatitudeBits }
        return lhs.toLongitudeBits < rhs.toLongitudeBits
    }
}

/// What the live short-search transfer computation returns for a pair.
nonisolated enum TransferWalkOutcome: Hashable, Sendable {
    case route(OfflineWalkingRoute)
    /// A deterministic routing failure: no pedestrian path exists.
    case noRoute
}

nonisolated enum TransferWalkTableError: Error, Equatable {
    case malformed(String)
    case unsupported(String)
}
