import Foundation

protocol TripDetailService: Sendable {
    nonisolated func tripDetail(for selection: TripDetailSelection,
        refreshPolicy: RouteRealtimeRefreshPolicy) async throws -> TripDetailSnapshot
}

nonisolated enum TripDetailError: Error, LocalizedError {
    case unavailable, obsoleteFeed
    var errorDescription: String? {
        switch self {
        case .unavailable: "Stop details are unavailable for this run."
        case .obsoleteFeed: "The timetable has changed. Plan your journey again to view this run."
        }
    }
}

struct UnavailableTripDetailService: TripDetailService {
    nonisolated func tripDetail(for _: TripDetailSelection,
        refreshPolicy _: RouteRealtimeRefreshPolicy) async throws -> TripDetailSnapshot {
        throw TripDetailError.unavailable
    }
}

struct FixtureTripDetailService: TripDetailService {
    let snapshot: TripDetailSnapshot
    nonisolated func tripDetail(for selection: TripDetailSelection,
        refreshPolicy _: RouteRealtimeRefreshPolicy) async throws -> TripDetailSnapshot {
        guard snapshot.instance == selection.instance else { throw TripDetailError.unavailable }
        return snapshot
    }
}
