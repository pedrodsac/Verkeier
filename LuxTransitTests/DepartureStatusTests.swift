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

    private func makeDeparture(
        realtimeDeparture: Date?,
        delayMinutes: Int?,
        isCancelled: Bool = false,
        isStatusUnknown: Bool = false
    ) -> Departure {
        Departure(
            id: "departure-1",
            stopId: "stop-1",
            lineName: "F1",
            destination: "Upper Station",
            scheduledDeparture: Date(timeIntervalSince1970: 1_800),
            realtimeDeparture: realtimeDeparture,
            delayMinutes: delayMinutes,
            isCancelled: isCancelled,
            isStatusUnknown: isStatusUnknown,
            dataSource: .mock
        )
    }
}
