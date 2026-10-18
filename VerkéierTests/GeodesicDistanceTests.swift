import Foundation
import Testing
@testable import Verkeier

/// A small seeded generator, so a failing sequence can be replayed.
nonisolated struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

@Suite("Geodesic distance")
struct GeodesicDistanceTests {
    /// Geoscience Australia's published Vincenty test line, Flinders Peak to Buninyong: 54,972.271 m.
    @Test func matchesAPublishedGeodesicTestLine() {
        let flinders = LocationPoint(
            latitude: -(37 + 57.0 / 60 + 3.72030 / 3600),
            longitude: 144 + 25.0 / 60 + 29.52440 / 3600
        )
        let buninyong = LocationPoint(
            latitude: -(37 + 39.0 / 60 + 10.15610 / 3600),
            longitude: 143 + 55.0 / 60 + 35.38390 / 3600
        )
        #expect(abs(GeodesicDistance.meters(from: flinders, to: buninyong) - 54_972.271) < 0.001)
    }

    @Test func isZeroForTheSamePointAndSymmetric() {
        let gare = LocationPoint(latitude: 49.6000, longitude: 6.1337)
        let kirchberg = LocationPoint(latitude: 49.6308, longitude: 6.1700)
        #expect(GeodesicDistance.meters(from: gare, to: gare) == 0)
        let forward = GeodesicDistance.meters(from: gare, to: kirchberg)
        let backward = GeodesicDistance.meters(from: kirchberg, to: gare)
        #expect(abs(forward - backward) < 1e-6)
        #expect(forward > 4_000 && forward < 5_000)
    }

    @Test func rejectsNonFiniteCoordinatesAndSurvivesAntipodes() {
        #expect(GeodesicDistance.meters(fromLatitude: .nan, fromLongitude: 6, toLatitude: 49, toLongitude: 6).isNaN)
        let nearAntipodal = GeodesicDistance.meters(
            fromLatitude: 0,
            fromLongitude: 0,
            toLatitude: 0.5,
            toLongitude: 179.7
        )
        #expect(nearAntipodal.isFinite && nearAntipodal > 19_000_000)
    }

    /// `CLLocation.distance(from:)` returns different values for one pair depending on the calls before it.
    @Test func returnsTheSameBitsForAPairWhateverWasCalculatedBefore() {
        var generator = SplitMix64(seed: 0xD157_A1CE)
        let pairs = (0..<64).map { _ -> (LocationPoint, LocationPoint) in
            let from = Self.point(&generator)
            let span = [0.0003, 0.002, 0.02, 0.1].randomElement(using: &generator)!
            return (
                from,
                LocationPoint(
                    latitude: from.latitude + Double.random(in: -span...span, using: &generator),
                    longitude: from.longitude + Double.random(in: -span...span, using: &generator)
                )
            )
        }
        let expected = pairs.map { GeodesicDistance.meters(from: $0.0, to: $0.1).bitPattern }
        var differing = 0
        for _ in 0..<20_000 {
            let index = Int.random(in: pairs.indices, using: &generator)
            if GeodesicDistance.meters(from: pairs[index].0, to: pairs[index].1).bitPattern != expected[index] {
                differing += 1
            }
        }
        #expect(differing == 0)
    }

    static func point(_ generator: inout SplitMix64) -> LocationPoint {
        LocationPoint(
            latitude: Double.random(in: 49.45...49.85, using: &generator),
            longitude: Double.random(in: 5.75...6.55, using: &generator)
        )
    }
}
