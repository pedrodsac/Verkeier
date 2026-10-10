import Foundation
import Testing
@testable import Verkeier

@Suite("Trip stop detail presentation")
@MainActor
struct TripDetailTests {
    private let anchor = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func passedStatusAndRideHighlightAreIndependent() throws {
        let selection = try selection()
        let entries = (1...5).map { stop($0, scheduledOffset: Double($0 - 3) * 60, delay: 0) }
        let rows = TripStopPresentation.rows(snapshot: snapshot(entries), selection: selection, now: anchor, refreshFailed: false)
        #expect(rows.map(\.isPassed) == [true, true, true, false, false])
        #expect(rows.map(\.isInRide) == [false, true, true, true, false])
        #expect(rows[4].statusTint == .green)
        #expect(rows[4].status == "On time")
        #expect(rows[4].liveTime == nil)
    }

    @Test func eachStopKeepsItsOwnDelayAndMissingReportsStayUnavailable() throws {
        let entries = [stop(1, scheduledOffset: -600, delay: 2, historical: true),
                       stop(2, scheduledOffset: 60, delay: 5), stop(3, scheduledOffset: 600, delay: nil),
                       stop(4, scheduledOffset: 900, delay: -1)]
        let rows = TripStopPresentation.rows(snapshot: snapshot(entries), selection: try selection(), now: anchor, refreshFailed: false)
        #expect(rows[0].status == "+2")
        #expect(rows[1].status == "+5")
        #expect(rows[2].liveTime == nil)
        #expect(rows[2].status == "Live time unavailable")
        #expect(rows[3].status == "-1")
        #expect(rows[3].accessibilityStatus == "1 minute early")
        #expect(rows[1].statusTint == .orange)
    }

    @Test func delayMatchesDisplayedMinutesAndOnTimeHasOneClockTime() throws {
        let entries = [59.0, 30.0, 0.0].enumerated().map { index, seconds in
            let value = TripStopTiming(scheduled: anchor.addingTimeInterval(600 + seconds),
                realtime: anchor.addingTimeInterval(600), isHistoricalReport: false,
                observedAt: anchor, isCancelled: false)
            return TripStopEntry(sequence: index + 1, stop: stop(index + 1).stop,
                arrival: value, departure: value, platform: "\(index + 1)")
        }
        let rows = TripStopPresentation.rows(snapshot: snapshot(entries), selection: try selection(), now: anchor, refreshFailed: false)
        #expect(rows.allSatisfy { $0.status == "On time" && $0.statusTint == .green && $0.liveTime == nil })
        #expect(rows.map(\.platform) == ["1", "2", "3"])
    }

    @Test func crossingDisplayedMinuteBoundaryHasSignedDelay() throws {
        let value = TripStopTiming(scheduled: anchor.addingTimeInterval(659),
            realtime: anchor.addingTimeInterval(660), isHistoricalReport: false,
            observedAt: anchor, isCancelled: false)
        let entry = TripStopEntry(sequence: 1, stop: stop(1).stop, arrival: value, departure: value, platform: nil)
        let row = try #require(TripStopPresentation.rows(snapshot: snapshot([entry]), selection: try selection(),
            now: anchor, refreshFailed: false).first)
        #expect(row.status == "+1")
        #expect(row.liveTime == value.realtime)
        #expect(row.statusTint == .orange)
    }

    @Test func timetableAdvancesProgressButIntermediateArrivalAloneDoesNot() throws {
        let arrival = timing(-300, delay: 0)
        let entries = [stop(1, scheduledOffset: -600, delay: nil),
            TripStopEntry(sequence: 2, stop: stop(2).stop, arrival: arrival,
                departure: timing(60, delay: 0), platform: nil), stop(3, scheduledOffset: 600, delay: nil)]
        let rows = TripStopPresentation.rows(snapshot: snapshot(entries), selection: try selection(), now: anchor, refreshFailed: false)
        #expect(rows.map(\.isPassed) == [true, false, false])
    }

    @Test func missingLiveDataUsesScheduleEvenWhenRefreshFails() throws {
        let entries = [-60.0, 0, 60].enumerated().map { index, offset in
            stop(index + 1, scheduledOffset: offset, delay: nil)
        }
        let rows = TripStopPresentation.rows(snapshot: snapshot(entries, liveDataAvailable: false),
            selection: try selection(), now: anchor, refreshFailed: true)
        #expect(rows.map(\.isPassed) == [true, true, false])
        #expect(rows.allSatisfy { $0.status == "Live time unavailable" && $0.liveTime == nil })
    }

    @Test func liveDelayTakesPrecedenceOverPastScheduledDeparture() throws {
        let entries = [stop(1, scheduledOffset: -60, delay: 5), stop(2, scheduledOffset: 600, delay: nil)]
        let rows = TripStopPresentation.rows(snapshot: snapshot(entries), selection: try selection(), now: anchor, refreshFailed: false)
        #expect(rows.allSatisfy { !$0.isPassed })
    }

    @Test func timetableUsesFinalArrivalButWaitsForIntermediateDeparture() throws {
        let entries = [TripStopEntry(sequence: 1, stop: stop(1).stop,
                arrival: timing(-60, delay: nil), departure: timing(60, delay: nil), platform: nil),
            TripStopEntry(sequence: 2, stop: stop(2).stop,
                arrival: timing(120, delay: nil), departure: nil, platform: nil)]
        let initial = TripStopPresentation.rows(snapshot: snapshot(entries), selection: try selection(), now: anchor, refreshFailed: false)
        #expect(initial.allSatisfy { !$0.isPassed })
        let later = TripStopPresentation.rows(snapshot: snapshot(entries), selection: try selection(),
            now: anchor.addingTimeInterval(120), refreshFailed: false)
        #expect(later.allSatisfy { $0.isPassed })
    }

    @Test func stalePredictionsDoNotAdvanceProgressButHistoricalReportsDo() throws {
        let entries = [stop(1, scheduledOffset: -600, delay: 1, historical: true, age: 300),
                       stop(2, scheduledOffset: -300, delay: 0, age: 300), stop(3, scheduledOffset: 600, delay: 1)]
        let rows = TripStopPresentation.rows(snapshot: snapshot(entries), selection: try selection(), now: anchor, refreshFailed: false)
        #expect(rows.map(\.isPassed) == [true, false, false])
        #expect(rows[1].statusTint == .secondary)
        #expect(rows[1].status.contains("Stale"))
        #expect(rows[0].statusTint == .orange)
    }

    @Test func cancelledRunDoesNotAppearToHavePassedByItsTimetable() throws {
        let entries = [stop(1, scheduledOffset: -600, delay: nil), stop(2, scheduledOffset: -300, delay: nil)]
        let rows = TripStopPresentation.rows(snapshot: snapshot(entries, cancelled: true), selection: try selection(), now: anchor, refreshFailed: false)
        #expect(rows.allSatisfy { !$0.isPassed && $0.status == "Cancelled" && $0.statusTint == .red })
    }

    @Test func failedRefreshKeepsRowsAndMarksLiveDataStale() async throws {
        let model = TripDetailViewModel(now: { anchor })
        model.select(try selection())
        await model.refresh(using: FixtureTripDetailService(snapshot: snapshot([stop(2, scheduledOffset: 600, delay: 3)])))
        let first = model.snapshot
        await model.refresh(using: FailingTripDetailService())
        #expect(model.snapshot == first)
        #expect(model.rows.count == 1)
        #expect(model.rows[0].statusTint == .secondary)
        #expect(model.refreshFailed)
        #expect(model.errorMessage != nil)
    }

    @Test func changingSelectionOrLeavingRejectsInFlightResponse() async throws {
        for leave in [false, true] {
            let model = TripDetailViewModel(now: { anchor })
            model.select(try selection())
            let gate = TripDetailGate()
            let service = DelayedTripDetailService(snapshot: snapshot([stop(2)]), gate: gate)
            let task = Task { await model.refresh(using: service) }
            await gate.waitUntilEntered()
            if leave { model.deactivate() } else { model.select(try selection(tripID: "other")) }
            await gate.release()
            await task.value
            #expect(model.snapshot == nil)
            #expect(model.rows.isEmpty)
        }
    }

    @Test func missingHistoricalReportsAreRetainedOnSuccessfulRefresh() async throws {
        let model = TripDetailViewModel(now: { anchor })
        model.select(try selection())
        await model.refresh(using: FixtureTripDetailService(snapshot: snapshot([stop(1, scheduledOffset: -600, delay: 2, historical: true)])))
        await model.refresh(using: FixtureTripDetailService(snapshot: snapshot([stop(1, scheduledOffset: -600, delay: nil)])))
        #expect(model.rows[0].status == "+2")
        #expect(model.rows[0].isPassed)
    }

    @Test func nativeNavigationSelectionIncludesServiceDayAndOccurrences() throws {
        let selection = try selection()
        #expect(selection.instance.serviceDate == "20261009")
        #expect(TransitSheetRoute.tripDetail(selection).defaultDetent == .medium)
        let leg = leg()
        let item = try #require(RouteTimelineBuilder.items(from: [leg]).compactMap { item -> SegmentNode? in
            if case let .segment(segment) = item { return segment }; return nil
        }.first)
        #expect(item.tripSelection == selection)
        let data = try JSONEncoder().encode(leg)
        #expect(try JSONDecoder().decode(RoutePlan.Leg.self, from: data).tripInstance == leg.tripInstance)
    }

    private func selection(tripID: String = "trip") throws -> TripDetailSelection {
        var value = leg()
        value.tripInstance = .init(feedGeneration: 1, tripID: tripID, serviceDate: "20261009")
        return try #require(TripDetailSelection(leg: value))
    }

    private func leg() -> RoutePlan.Leg {
        var value = RoutePlan.Leg(id: "leg", mode: .bus, transportKind: .transit, routeName: "850", headsign: "Airport",
            origin: .init(latitude: 49.6, longitude: 6.1), destination: .init(latitude: 49.7, longitude: 6.2))
        value.tripInstance = .init(feedGeneration: 1, tripID: "trip", serviceDate: "20261009")
        value.boardingStopSequence = 2
        value.alightingStopSequence = 4
        return value
    }

    private func timing(_ offset: TimeInterval, delay: Int?, historical: Bool = false, age: TimeInterval = 0) -> TripStopTiming {
        .init(scheduled: anchor.addingTimeInterval(offset),
            realtime: delay.map { anchor.addingTimeInterval(offset + Double($0) * 60) },
            isHistoricalReport: historical, observedAt: anchor.addingTimeInterval(-age), isCancelled: false)
    }

    private func stop(_ sequence: Int, scheduledOffset: TimeInterval = 600, delay: Int? = 0,
        historical: Bool = false, age: TimeInterval = 0) -> TripStopEntry {
        let value = timing(scheduledOffset, delay: delay, historical: historical, age: age)
        return .init(sequence: sequence, stop: .init(id: "stop", name: "Stop \(sequence)",
            location: .init(latitude: 49.6 + Double(sequence) * 0.01, longitude: 6.1), modes: [.bus], dataSource: .mock),
            arrival: value, departure: value, platform: "1")
    }

    private func snapshot(_ stops: [TripStopEntry], cancelled: Bool = false, liveDataAvailable: Bool = true) -> TripDetailSnapshot {
        .init(instance: .init(feedGeneration: 1, tripID: "trip", serviceDate: "20261009"), stops: stops,
            mapOverlay: .init(segments: []), isApproximateRoute: false, liveDataAvailable: liveDataAvailable,
            isCancelled: cancelled, fetchedAt: anchor)
    }
}

private struct FailingTripDetailService: TripDetailService {
    nonisolated func tripDetail(for _: TripDetailSelection, refreshPolicy _: RouteRealtimeRefreshPolicy) async throws -> TripDetailSnapshot {
        throw URLError(.notConnectedToInternet)
    }
}

private struct DelayedTripDetailService: TripDetailService {
    let snapshot: TripDetailSnapshot
    let gate: TripDetailGate
    nonisolated func tripDetail(for _: TripDetailSelection, refreshPolicy _: RouteRealtimeRefreshPolicy) async throws -> TripDetailSnapshot {
        await gate.enter()
        return snapshot
    }
}

private actor TripDetailGate {
    var entered = false
    var waiter: CheckedContinuation<Void, Never>?
    var enteredWaiter: CheckedContinuation<Void, Never>?
    func enter() async {
        entered = true
        enteredWaiter?.resume(); enteredWaiter = nil
        await withCheckedContinuation { waiter = $0 }
    }
    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiter = $0 }
    }
    func release() { waiter?.resume(); waiter = nil }
}
