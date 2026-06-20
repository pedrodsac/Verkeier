import Foundation
import Testing

@testable import LuxTransit

struct DepartureStatusTests {
    @Test func missingRealtimeValueIsScheduled() {
        let departure = makeDeparture(
            realtimeDeparture: nil,
            delayMinutes: nil
        )

        #expect(departure.status == .scheduled)
        #expect(departure.status.displayText == "Scheduled")
    }

    @Test func zeroDelayIsOnTime() {
        let departure = makeDeparture(
            realtimeDeparture: Date(timeIntervalSince1970: 1_800),
            delayMinutes: 0
        )

        #expect(departure.status == .onTime)
        #expect(departure.status.displayText == "On time")
    }

    @Test func positiveDelayDisplaysMinutes() {
        let departure = makeDeparture(
            realtimeDeparture: Date(timeIntervalSince1970: 2_100),
            delayMinutes: 5
        )

        #expect(departure.status == .delayed(minutes: 5))
        #expect(departure.status.displayText == "+5 min")
    }

    @Test func cancelledOverridesDelay() {
        let departure = makeDeparture(
            realtimeDeparture: Date(timeIntervalSince1970: 2_100),
            delayMinutes: 5,
            isCancelled: true
        )

        #expect(departure.status == .cancelled)
        #expect(departure.status.displayText == "Cancelled")
    }

    @Test func explicitUnknownOverridesMissingDelay() {
        let departure = makeDeparture(
            realtimeDeparture: Date(timeIntervalSince1970: 1_800),
            delayMinutes: nil,
            isStatusUnknown: true
        )

        #expect(departure.status == .unknown)
        #expect(departure.status.displayText == "Unknown")
    }

    @Test func nextTrackableDepartureChoosesEarliestUpcomingNonCancelledDeparture() {
        let now = Date(timeIntervalSince1970: 1_000)
        let cancelledSoon = makeDeparture(
            id: "cancelled",
            scheduledDeparture: now.addingTimeInterval(60),
            realtimeDeparture: now.addingTimeInterval(60),
            delayMinutes: 0,
            isCancelled: true
        )
        let later = makeDeparture(
            id: "later",
            scheduledDeparture: now.addingTimeInterval(300),
            realtimeDeparture: now.addingTimeInterval(300),
            delayMinutes: 0
        )

        #expect(
            DepartureTrackingSelection.nextTrackableDeparture(
                from: [later, cancelledSoon],
                now: now
            )?.id == "later"
        )
    }

    @Test func trackedDepartureFindsRefreshedDepartureById() {
        let departure = makeDeparture(id: "tracked")

        #expect(
            DepartureTrackingSelection.trackedDeparture(
                in: [makeDeparture(id: "other"), departure],
                trackedDepartureId: "tracked"
            ) == departure
        )
    }

    private func makeDeparture(
        id: String = "departure-1",
        scheduledDeparture: Date = Date(timeIntervalSince1970: 1_800),
        realtimeDeparture: Date? = nil,
        delayMinutes: Int? = nil,
        isCancelled: Bool = false,
        isStatusUnknown: Bool = false
    ) -> Departure {
        Departure(
            id: id,
            stopId: "stop-1",
            lineName: "F1",
            destination: "Upper Station",
            scheduledDeparture: scheduledDeparture,
            realtimeDeparture: realtimeDeparture,
            delayMinutes: delayMinutes,
            isCancelled: isCancelled,
            isStatusUnknown: isStatusUnknown,
            dataSource: .mock
        )
    }
}
