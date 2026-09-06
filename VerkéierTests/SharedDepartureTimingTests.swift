import Foundation
import Testing

@testable import Verkeier

struct SharedDepartureTimingTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func countdownRoundsUpcomingDeparturesUp() {
        #expect(
            SharedDepartureTiming.countdownMinutes(
                until: now.addingTimeInterval(60),
                from: now
            ) == 1
        )
        #expect(
            SharedDepartureTiming.countdownMinutes(
                until: now.addingTimeInterval(61),
                from: now
            ) == 2
        )
    }

    @Test func countdownUsesNowNearAndAfterDeparture() {
        #expect(
            SharedDepartureTiming.countdownMinutes(
                until: now.addingTimeInterval(30),
                from: now
            ) == 0
        )
        #expect(
            SharedDepartureTiming.countdownMinutes(
                until: now.addingTimeInterval(-60),
                from: now
            ) == 0
        )
    }

    @Test func departureRemainsVisibleForFollowingMinute() {
        #expect(SharedDepartureTiming.isVisible(now.addingTimeInterval(-60), at: now))
        #expect(!SharedDepartureTiming.isVisible(now.addingTimeInterval(-60.001), at: now))
    }
}
