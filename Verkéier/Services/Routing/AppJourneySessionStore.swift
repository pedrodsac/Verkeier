import Foundation
import MobiliteitKit

/// Holds the package session for this injected app service; contains no search policy.
actor AppJourneySessionStore {
    private let planner: JourneyPlanner
    private var session: JourneyResultSession?
    private var preparedRouter: TransitRouter?
    private var request: JourneyPlanningRequest?
    private var databaseURL: URL?
    private var generation = 0
    private let bikePlanner: BikeShareRoutePlanner
    private var supplementalOptions: [RouteOption] = []
    init(planner: JourneyPlanner, bikePlanner: BikeShareRoutePlanner) {
        self.planner = planner; self.bikePlanner = bikePlanner
    }

    func calculate(databaseURL: URL, request: JourneyPlanningRequest,
                   page: JourneyPlanningPage, refresh: JourneyRefreshPolicy,
                   origin: LocationPoint, destination: LocationPoint, time: RoutePlanningTime
    ) async throws -> (result: JourneyPlanningResult?, supplemental: [RouteOption]) {
        generation += 1
        let current = generation
        let router = try await planner.router(for: databaseURL)
        guard current == generation else { throw JourneyPlanningError.supersededRequest }
        let isNewRequest = self.request != request || self.databaseURL != databaseURL || session == nil || preparedRouter !== router
        if isNewRequest {
            supplementalOptions = []
            let created = try await planner.makePlanningSession(databaseURL: databaseURL, request: request)
            guard current == generation else { throw JourneyPlanningError.supersededRequest }
            session = created; preparedRouter = router; self.request = request; self.databaseURL = databaseURL
        }
        guard let session else { throw JourneyPlanningError.supersededRequest }
        let isInitialPage: Bool
        if case .initial = page { isInitialPage = true } else { isInitialPage = false }
        async let bike = isNewRequest || isInitialPage || refresh == .forceRefresh
            ? bikePlanner.option(from: origin, to: destination, time: time)
            : supplementalOptions.first
        let result: JourneyPlanningResult?
        do {
            result = try await session.calculate(page: page, refresh: refresh, now: .now)
        } catch JourneyPlanningError.noRouteFound {
            result = nil
        }
        let option = await bike
        try Task.checkCancellation()
        guard current == generation else { throw JourneyPlanningError.supersededRequest }
        guard result != nil || option != nil else { throw JourneyPlanningError.noRouteFound }
        supplementalOptions = option.map { [$0] } ?? []
        return (result, supplementalOptions)
    }

    func submit(_ option: RouteOption, replacing original: RouteOption) async throws -> (result: JourneyPlanningResult, supplemental: [RouteOption])? {
        guard let session, let token = option.refinementToken else { return nil }
        let current = generation
        var result: JourneyPlanningResult?
        for leg in option.plan.legs where leg.transportKind == .walking {
            // Submit only measured spans or walks whose timing changed with them.
            // Unchanged presentation legs must not rewrite the native walking cache.
            if let previous = original.plan.legs.first(where: { $0.nativeWalkingRange == leg.nativeWalkingRange }),
               previous == leg { continue }
            guard let range = leg.nativeWalkingRange,
                  let departure = leg.departureTime, let arrival = leg.arrivalTime else { continue }
            let seconds = arrival.timeIntervalSince(departure)
            guard seconds.isFinite, seconds >= 0, seconds <= Double(Int.max) else { continue }
            result = try await session.submitWalkingRefinement(.init(token: token, range: range,
                route: .init(durationSeconds: Int(seconds.rounded()), distanceMeters: leg.distanceMeters ?? 0,
                    polyline: leg.mapCoordinates.map { .init(latitude: $0.latitude, longitude: $0.longitude) },
                    evidence: leg.walkingEvidence == .estimate ? .estimate : .routedPedestrian),
                departure: departure, arrival: arrival))
            guard current == generation else { throw JourneyPlanningError.staleRefinement }
            if result?.invalidatedIDs.contains(token.journeyID) == true { break }
        }
        return result.map { ($0, supplementalOptions) }
    }

    func refreshRealtime(optionID: String, origin: JourneyEndpoint, destination: JourneyEndpoint, force: Bool) async throws
        -> (result: JourneyPlanningResult, supplemental: [RouteOption])? {
        guard let session, request?.origin == origin, request?.destination == destination else { return nil }
        let current = generation
        let result = try await session.refreshDisplayedRealtime(journeyID: .init(optionID),
            refresh: force ? .forceRefresh : .useCache)
        guard current == generation else { throw JourneyPlanningError.supersededRequest }
        return (result, supplementalOptions)
    }
}

// Compatibility for fixtures that inject a prepared package engine.
typealias MobiliteitRouteEngine = JourneyPlanner

extension RoutePlanningTime {
    nonisolated var packageTime: JourneyPlanningTime {
        switch self {
        case .leaveNow: .now
        case let .departAt(date): .departAt(date)
        case let .arriveBy(date): .arriveBy(date)
        }
    }
}
extension RoutePlannerFilters {
    nonisolated var packagePreferences: RoutingPreferences {
        let preferred: TransitModeMask? = switch modePreference {
        case .any: nil
        case .bus: .init(rawValue: 1 << 3)
        case .tram: .init(rawValue: 1 << 0)
        case .train: .init(rawValue: (1 << 1) | (1 << 2))
        }
        return .init(preferredMode: preferred, avoidTightTransfers: avoidTightTransfers)
    }
}
extension RouteSearchPage {
    nonisolated var packagePage: JourneyPlanningPage {
        switch self {
        case .initial: .initial
        case .earlierAdjacent: .earlier
        case .laterAdjacent: .later
        case let .earlier(date, limit): .before(date, nil, limit)
        case let .later(date, limit): .after(date, nil, limit)
        case let .earlierFrom(date, id, limit): .before(date, .init(id), limit)
        case let .laterFrom(date, id, limit): .after(date, .init(id), limit)
        }
    }
}
extension RouteRealtimeRefreshPolicy {
    nonisolated var packagePolicy: JourneyRefreshPolicy {
        switch self {
        case .scheduleOnly: .scheduleOnly
        case .useCache: .useCache
        case .forceRefresh: .forceRefresh
        }
    }
}
