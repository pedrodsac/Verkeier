import Foundation
import Testing
@testable import Verkeier

@Suite("Package route result presentation")
@MainActor
struct RouteOptionDeduplicationTests {
    private let anchor = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Non-dominated package alternatives and recommendation pass through unchanged")
    func keepsPackageChoices() async {
        let options = [option(id: "first", duration: 1_200), option(id: "recommended", departure: 900, duration: 1_500)]
        let model = configuredModel()
        await model.calculateRoute(using: PackageResultFixture(options: options, recommended: "recommended"), from: nil)
        #expect(model.routeOptions.map(\.id) == options.map(\.id))
        #expect(model.selectedRouteOptionID == "recommended")
        #expect(model.canLoadEarlierRoutes)
        #expect(!model.canLoadLaterRoutes)
    }

    @Test("A package snapshot replaces the displayed result set")
    func acceptsReplacementSnapshot() async {
        let model = configuredModel()
        await model.calculateRoute(using: PackageResultFixture(options: [option(id: "old", duration: 1_200)], recommended: "old"), from: nil)
        model.canLoadLaterRoutes = true
        await model.loadLaterRoutes(using: PackageResultFixture(options: [option(id: "replacement", duration: 1_500)], recommended: "replacement"), from: nil)
        #expect(model.routeOptions.map(\.id) == ["replacement"])
        #expect(model.selectedRouteOptionID == "replacement")
    }

    @Test("A selectable manual choice survives a new package recommendation")
    func preservesManualSelection() async {
        let options = [option(id: "first", duration: 1_200), option(id: "second", departure: 900, duration: 1_500)]
        let model = configuredModel()
        await model.calculateRoute(using: PackageResultFixture(options: options, recommended: "first"), from: nil)
        model.selectRouteOption(id: "second")
        await model.calculateRoute(using: PackageResultFixture(options: options, recommended: "first"), from: nil)
        #expect(model.selectedRouteOptionID == "second")
    }

    @Test("A dominated recommendation falls back to the faster route")
    func dominatedRecommendationFallsBack() async {
        let slow = option(id: "slow", departure: 300, duration: 1_800)
        let fast = option(id: "fast", departure: 600, duration: 900)
        let model = configuredModel()
        await model.calculateRoute(using: PackageResultFixture(options: [slow, fast], recommended: slow.id), from: nil)
        #expect(model.routeOptions.map(\.id) == [fast.id])
        #expect(model.selectedRouteOptionID == fast.id)
        #expect(model.unfilteredRouteOptions.map(\.id) == [slow.id, fast.id])
    }

    @Test("Paging hides a dominated manual choice and selects its faster replacement")
    func pagingReplacesDominatedManualSelection() async {
        let slow = option(id: "slow", departure: 300, duration: 1_800)
        let fast = option(id: "fast", departure: 600, duration: 900)
        let model = configuredModel()
        await model.calculateRoute(using: PackageResultFixture(options: [slow], recommended: slow.id, canLoadLater: true), from: nil)
        model.selectRouteOption(id: slow.id)
        await model.loadLaterRoutes(using: PackageResultFixture(options: [slow, fast], recommended: fast.id), from: nil)
        #expect(model.routeOptions.map(\.id) == [fast.id])
        #expect(model.selectedRouteOptionID == fast.id)
    }

    private func configuredModel() -> TransitMapViewModel {
        let model = TransitMapViewModel(now: { anchor })
        model.routeOrigin = RoutePlace(title: "Origin", location: .init(latitude: 49.6, longitude: 6.1), source: .search)
        model.routeDestination = RoutePlace(title: "Destination", location: .init(latitude: 49.61, longitude: 6.1), source: .search)
        model.routePlanningTime = .departAt(anchor)
        return model
    }

    private func option(id: String, departure: TimeInterval = 300, duration: TimeInterval) -> RouteOption {
        let origin = LocationPoint(latitude: 49.6, longitude: 6.1)
        let destination = LocationPoint(latitude: 49.61, longitude: 6.1)
        let leg = RoutePlan.Leg(id: id, mode: .bus, transportKind: .transit,
            origin: origin, destination: destination, departureTime: anchor.addingTimeInterval(departure),
            arrivalTime: anchor.addingTimeInterval(departure + duration))
        return RouteOption(id: id, plan: .init(id: id, origin: origin, destination: destination,
            expectedTravelTime: duration, distanceMeters: 0, legs: [leg], dataSource: .local), mapOverlay: nil)
    }
}

private struct PackageResultFixture: RouteService {
    let options: [RouteOption]
    let recommended: String
    var canLoadLater = false
    nonisolated func calculateRoute(from: LocationPoint, to: LocationPoint,
        time: RoutePlanningTime, filters: RoutePlannerFilters,
        realtimeRefreshPolicy: RouteRealtimeRefreshPolicy, page: RouteSearchPage
    ) async throws -> RouteCalculation {
        var result = RouteCalculation(options: options, selectedOptionID: recommended)
        result.isAuthoritativeSnapshot = true
        result.canLoadEarlier = true
        result.canLoadLater = canLoadLater
        return result
    }
    @MainActor func openInAppleMaps(from: LocationPoint, to: LocationPoint) {}
}
