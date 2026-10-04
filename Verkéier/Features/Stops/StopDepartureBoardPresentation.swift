import Foundation

/// Immutable, prepared board data shared by the list and its toolbar.
struct StopDepartureBoardPresentation {
    struct Inputs: Equatable {
        let stopID: String
        let routes: [TransitRoute]
        let liveDepartures: [Departure]
        let scheduledDepartures: [OfflineScheduleDeparture]
        let useScheduledFallback: Bool
        let selectedLine: String?
        let selectedPlatform: String?
        var localeIdentifier = Locale.current.identifier
    }

    let availablePlatforms: [String]
    let visibleLiveDepartures: [Departure]
    let visibleScheduledDepartures: [Departure]
    let visibleDepartures: [Departure]

    init(inputs: Inputs) {
        let locale = Locale(identifier: inputs.localeIdentifier)
        let live = Self.unique(inputs.liveDepartures, locale: locale)
        let scheduled = inputs.useScheduledFallback
            ? Self.unique(inputs.scheduledDepartures.map { departure in
                Departure(
                    id: departure.id,
                    stopId: inputs.stopID,
                    lineName: departure.lineName,
                    destination: departure.destination,
                    scheduledDeparture: departure.departureDate,
                    platform: departure.platform,
                    dataSource: .gtfs
                )
            }, locale: locale)
            : []
        let route = inputs.routes.first { $0.id == inputs.selectedLine }
        let lineFilteredLive = Self.lineFiltered(live, route: route)
        let lineFilteredScheduled = Self.lineFiltered(scheduled, route: route)
        let active = inputs.useScheduledFallback ? lineFilteredScheduled : lineFilteredLive

        var platforms = Set<String>()
        availablePlatforms = active.compactMap { departure in
            guard let platform = departure.platform?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !platform.isEmpty, platforms.insert(platform).inserted else { return nil }
            return platform
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        visibleLiveDepartures = Self.platformFiltered(lineFilteredLive, platform: inputs.selectedPlatform)
        visibleScheduledDepartures = Self.platformFiltered(lineFilteredScheduled, platform: inputs.selectedPlatform)
        visibleDepartures = (inputs.useScheduledFallback ? visibleScheduledDepartures : visibleLiveDepartures)
            .enumerated()
            .sorted { lhs, rhs in
                let lhsTime = lhs.element.realtimeDeparture ?? lhs.element.scheduledDeparture ?? .distantFuture
                let rhsTime = rhs.element.realtimeDeparture ?? rhs.element.scheduledDeparture ?? .distantFuture
                return lhsTime == rhsTime ? lhs.offset < rhs.offset : lhsTime < rhsTime
            }
            .map(\.element)
    }

    private static func lineFiltered(_ departures: [Departure], route: TransitRoute?) -> [Departure] {
        guard let route else { return departures }
        return departures.filter {
            $0.routeId?.caseInsensitiveCompare(route.id) == .orderedSame
                || $0.lineName.caseInsensitiveCompare(route.shortName) == .orderedSame
        }
    }

    private static func platformFiltered(_ departures: [Departure], platform: String?) -> [Departure] {
        guard let platform else { return departures }
        return departures.filter { $0.platform == platform }
    }

    private struct JourneyKey: Hashable {
        let line: String
        let destination: String
    }

    /// Preserve the first row for an ID or scheduled journey, including the
    /// existing inclusive one-minute tolerance. Each accepted journey occupies
    /// one minute bucket; only its bucket and two neighbours can match a row.
    private static func unique(_ departures: [Departure], locale: Locale) -> [Departure] {
        var ids = Set<String>()
        var times: [JourneyKey: [Double: Date]] = [:]
        var result: [Departure] = []
        result.reserveCapacity(departures.count)
        for departure in departures {
            guard !ids.contains(departure.id) else { continue }
            if let time = departure.scheduledDeparture,
               time.timeIntervalSinceReferenceDate.isFinite {
                let key = JourneyKey(
                    line: normalized(departure.lineName, locale: locale),
                    destination: normalized(departure.destination, locale: locale)
                )
                let bucket = floor(time.timeIntervalSinceReferenceDate / 60)
                let duplicate = [bucket - 1, bucket, bucket + 1].contains { neighbour in
                    guard let accepted = times[key]?[neighbour] else { return false }
                    return abs(time.timeIntervalSince(accepted)) <= 60
                }
                if duplicate { continue }
                times[key, default: [:]][bucket] = time
            }
            ids.insert(departure.id)
            result.append(departure)
        }
        return result
    }

    private static func normalized(_ text: String, locale: Locale) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: locale)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Owned by observable state, with explicit value inputs for invalidation.
/// Cache writes are not observable and cannot trigger another SwiftUI update.
struct StopDepartureBoardCache {
    private var inputs: StopDepartureBoardPresentation.Inputs?
    private var board: StopDepartureBoardPresentation?

    mutating func presentation(for inputs: StopDepartureBoardPresentation.Inputs) -> StopDepartureBoardPresentation {
        if self.inputs == inputs, let board { return board }
        let board = StopDepartureBoardPresentation(inputs: inputs)
        self.inputs = inputs
        self.board = board
        return board
    }
}
