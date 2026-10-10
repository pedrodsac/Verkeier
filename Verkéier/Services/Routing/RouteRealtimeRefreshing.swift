import Foundation
import MobiliteitKit

/// Optional refresh of one route, independent of search or paging.
protocol RouteRealtimeRefreshing: Sendable {
    nonisolated func refreshRouteRealtime(optionID: String, from origin: LocationPoint,
        to destination: LocationPoint, refreshPolicy: RouteRealtimeRefreshPolicy) async throws -> RouteCalculation?
}

extension MobiliteitRouteService: RouteRealtimeRefreshing {
    nonisolated func refreshRouteRealtime(optionID: String, from origin: LocationPoint,
        to destination: LocationPoint, refreshPolicy: RouteRealtimeRefreshPolicy) async throws -> RouteCalculation? {
        guard engine.hasRealtimeProvider, refreshPolicy != .scheduleOnly,
              let snapshot = try await sessions.refreshRealtime(
                optionID: optionID, origin: Self.journeyEndpoint(for: origin), destination: Self.journeyEndpoint(for: destination),
                force: refreshPolicy == .forceRefresh)
        else { return nil }
        return calculation(from: snapshot.result, origin: origin, destination: destination,
                           supplemental: snapshot.supplemental)
    }
}
