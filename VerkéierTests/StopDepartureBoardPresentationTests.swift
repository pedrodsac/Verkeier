import Foundation
import Testing

@testable import Verkeier

@MainActor
struct StopDepartureBoardPresentationTests {
    @Test func deduplicationPreservesFirstPredictionAndInclusiveMinuteTolerance() {
        let rows = [
            departure("first", time: 59, realtime: 600),
            departure("duplicate", time: 119, line: " t1 ", destination: " GÁRE "),
            departure("next", time: 120),
            departure("first", time: 500),
            departure("other-headsign", time: 59, destination: "Airport"),
            departure("no-time", time: nil),
            departure("another-no-time", time: nil)
        ]
        let board = StopDepartureBoardPresentation(inputs: inputs(live: rows))
        #expect(board.visibleLiveDepartures.map(\.id) == [
            "first", "next", "other-headsign", "no-time", "another-no-time"
        ])
        #expect(board.visibleLiveDepartures.first?.realtimeDeparture == Date(timeIntervalSinceReferenceDate: 600))
    }

    @Test func droppedRowDoesNotSuppressLaterJourneyOrReuseItsID() {
        let rows = [departure("a", time: -1), departure("b", time: 59), departure("b", time: 60)]
        #expect(StopDepartureBoardPresentation(inputs: inputs(live: rows))
            .visibleLiveDepartures.map(\.id) == ["a", "b"])
    }

    @Test func displayedOrderUsesPredictionsAndRetainsTies() {
        let rows = [departure("late", time: 1, realtime: 200),
                    departure("first-tie", time: 100, destination: "Airport"),
                    departure("second-tie", time: 100, destination: "Central")]
        #expect(StopDepartureBoardPresentation(inputs: inputs(live: rows))
            .visibleDepartures.map(\.id) == ["first-tie", "second-tie", "late"])
    }

    @Test func lineAndPlatformFiltersKeepAllLinePlatformsAvailable() {
        let route = TransitRoute(id: "route", shortName: "T1", mode: .tram, dataSource: .mock)
        let board = StopDepartureBoardPresentation(inputs: .init(
            stopID: "stop", routes: [route],
            liveDepartures: [departure("a", time: 0, platform: "1"),
                             departure("b", time: 300, platform: "2"),
                             departure("other", time: 600, line: "18", platform: "3")],
            scheduledDepartures: [], useScheduledFallback: false,
            selectedLine: "route", selectedPlatform: "2"
        ))
        #expect(board.availablePlatforms == ["1", "2"])
        #expect(board.visibleDepartures.map(\.id) == ["b"])
    }

    @Test func cachedBoardRefreshesMetadataFiltersSourceAndStop() {
        var cache = StopDepartureBoardCache()
        let original = inputs(live: [departure("a", time: 100, platform: "1")])
        #expect(cache.presentation(for: original).availablePlatforms == ["1"])
        #expect(cache.presentation(for: original).visibleDepartures.map(\.id) == ["a"])

        let changed = inputs(live: [departure("a", time: 100, platform: "2")])
        #expect(cache.presentation(for: changed).availablePlatforms == ["2"])

        let fallback = StopDepartureBoardPresentation.Inputs(
            stopID: "other-stop", routes: [], liveDepartures: original.liveDepartures,
            scheduledDepartures: [.init(id: "offline", lineName: "16", destination: "Gare",
                departureDate: Date(timeIntervalSinceReferenceDate: 500), platform: "3", mode: .bus)],
            useScheduledFallback: true, selectedLine: nil, selectedPlatform: "3"
        )
        let board = cache.presentation(for: fallback)
        #expect(board.availablePlatforms == ["3"])
        #expect(board.visibleDepartures.map(\.id) == ["offline"])
        #expect(board.visibleDepartures.first?.stopId == "other-stop")
        #expect(board.visibleDepartures.first?.dataSource == .gtfs)
        #expect(cache.presentation(for: original).visibleScheduledDepartures.isEmpty)
    }

    @Test func indexedDeduplicationMatchesJourneyRulesForUnsortedBoards() {
        // Exercise non-transitive tolerance, repeated IDs, nil times, distinct
        // destinations, diacritics, and minute boundaries in a shuffled feed.
        let rows: [Departure] = (0..<400).map { index in
            let time: Double? = index % 17 == 0 ? nil : Double((index * 137) % 3600 - 1800)
            let line = index % 2 == 0 ? "T1" : " t1 "
            let destination = index % 3 == 0 ? "Gáre" : "Airport"
            return departure("id-\(index % 311)", time: time, line: line, destination: destination)
        }
        var expected: [Departure] = []
        for row in rows {
            let duplicate = expected.contains { accepted in
                if accepted.id == row.id { return true }
                guard accepted.lineName.normalizedForSearch == row.lineName.normalizedForSearch,
                      accepted.destination.normalizedForSearch == row.destination.normalizedForSearch,
                      let first = accepted.scheduledDeparture, let second = row.scheduledDeparture else { return false }
                return abs(first.timeIntervalSince(second)) <= 60
            }
            if !duplicate { expected.append(row) }
        }
        #expect(StopDepartureBoardPresentation(inputs: inputs(live: rows)).visibleLiveDepartures == expected)
    }

    private func inputs(live: [Departure]) -> StopDepartureBoardPresentation.Inputs {
        .init(stopID: "stop", routes: [], liveDepartures: live, scheduledDepartures: [],
              useScheduledFallback: false, selectedLine: nil, selectedPlatform: nil)
    }

    private func departure(_ id: String, time: Double?, realtime: Double? = nil,
                           line: String = "T1", destination: String = "Gare", platform: String? = nil) -> Departure {
        Departure(id: id, stopId: "stop", lineName: line, destination: destination,
                  scheduledDeparture: time.map { Date(timeIntervalSinceReferenceDate: $0) },
                  realtimeDeparture: realtime.map { Date(timeIntervalSinceReferenceDate: $0) },
                  platform: platform, dataSource: .atpOpenAPI)
    }
}
