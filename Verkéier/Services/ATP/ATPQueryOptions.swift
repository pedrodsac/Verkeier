import Foundation

/// ATP product flags documented by mobiliteit.lu. The values can be combined
/// into the `products` query parameter.
struct ATPProductFilter: OptionSet, Codable, Hashable, Sendable {
    let rawValue: Int

    static let expressTrain = ATPProductFilter(rawValue: 1)
    static let nationalTrain = ATPProductFilter(rawValue: 2)
    static let localTrain = ATPProductFilter(rawValue: 4)
    static let bus = ATPProductFilter(rawValue: 32)
    static let tram = ATPProductFilter(rawValue: 256)

    static let trains: ATPProductFilter = [.expressTrain, .nationalTrain, .localTrain]
    static let publicTransport: ATPProductFilter = [.trains, .bus, .tram]
}

enum ATPRealtimeMode: String, Codable, CaseIterable, Sendable {
    case full = "FULL"
    case off = "OFF"
}

/// Explicit, bounded controls for a nearby-stop ATP request.
struct ATPNearbyStopsOptions: Hashable, Sendable {
    var radiusMeters: Int = 1_500
    var maximumResults: Int = 50
    var products: ATPProductFilter? = nil
    var language: String = "fr"

    var normalized: Self {
        var copy = self
        copy.radiusMeters = min(max(radiusMeters, 100), 5_000)
        copy.maximumResults = min(max(maximumResults, 1), 100)
        copy.language = language.isEmpty ? "fr" : language
        return copy
    }
}

/// Explicit, bounded controls for a departure-board ATP request.
struct ATPDepartureBoardOptions: Hashable, Sendable {
    var directionStopID: String? = nil
    var date: Date? = nil
    var durationMinutes: Int = 120
    var maximumJourneys: Int = 20
    var products: ATPProductFilter? = nil
    var operators: [String] = []
    var lines: [String] = []
    var platforms: [String] = []
    var realtimeMode: ATPRealtimeMode = .full
    var includePasslist = false
    var language: String = "fr"

    var normalized: Self {
        var copy = self
        copy.durationMinutes = min(max(durationMinutes, 0), 1_439)
        copy.maximumJourneys = min(max(maximumJourneys, 1), 100)
        copy.operators = Self.clean(copy.operators)
        copy.lines = Self.clean(copy.lines)
        copy.platforms = Self.clean(copy.platforms)
        copy.directionStopID = Self.clean(copy.directionStopID.map { [$0] } ?? []).first
        copy.language = language.isEmpty ? "fr" : language
        return copy
    }

    private static func clean(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count <= 100 else { return nil }
            return seen.insert(value).inserted ? value : nil
        }
    }
}

/// Filter state shared by a stop board and a saved favourite. Technical
/// request IDs and passlist are deliberately excluded: they are managed by
/// the client for diagnostics and journey tracking respectively.
struct TransitBoardFilter: Codable, Hashable, Sendable {
    var products: ATPProductFilter? = nil
    var operators: [String] = []
    var destinationStopID: String? = nil
    var platforms: [String] = []
    var durationMinutes = 120
    var maximumJourneys = 20
    var realtimeMode: ATPRealtimeMode = .full

    func options(lines: [String] = []) -> ATPDepartureBoardOptions {
        ATPDepartureBoardOptions(
            directionStopID: destinationStopID,
            durationMinutes: durationMinutes,
            maximumJourneys: maximumJourneys,
            products: products,
            operators: operators,
            lines: lines,
            platforms: platforms,
            realtimeMode: realtimeMode
        ).normalized
    }
}
