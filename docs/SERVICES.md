# Services

All service protocols live in `Verkéier/Services/`. Every protocol has a
production implementation, at least one mock, and an empty stub. Inject via
SwiftUI `@Environment` — never construct services inside views.

## Dependency Injection

Entries are declared in `Verkéier/App/AppDependencies.swift`:

```swift
extension EnvironmentValues {
    @Entry var atpClient: any ATPClient = EmptyATPClient()
    @Entry var gtfsService: any GTFSService = LocalGTFSService()
    @Entry var gtfsUpdateController: GTFSUpdateController = GTFSUpdateController()
    @Entry var routeService: any RouteService = PublicTransportRouteService(
        gtfsService: LocalGTFSService(), atpClient: EmptyATPClient())
    @Entry var avlClient: any AVLClient = LiveAVLClient(feedURL: …)
    @Entry var liveActivityManager: LiveActivityManager = LiveActivityManager()
    @Entry var departureReminderService: DepartureReminderService = DepartureReminderService()
}
```

**Reading in a view:**
```swift
@Environment(\.atpClient) private var atpClient
@Environment(\.gtfsService) private var gtfsService
```

**Overriding in a preview:**
```swift
#Preview {
    MyView()
        .environment(\.atpClient, ATPMockClient())
        .environment(\.avlClient, MockAVLClient())
}
```

**In tests:** pass mock implementations directly to view model constructors
(view models take services as init parameters, not via `@Environment`).

### Implementations by service

| Protocol | Production | Test / Preview |
|---|---|---|
| `ATPClient` | `LiveATPClient` | `ATPMockClient`, `EmptyATPClient` |
| `GTFSService` | `LocalGTFSService` | `LocalGTFSService` with fixture data |
| `AVLClient` | `LiveAVLClient` | `MockAVLClient`, `EmptyAVLClient` |
| `RouteService` | `PublicTransportRouteService` | `MapKitRouteService` (MapKit-only fallback) |

`GTFSUpdateController`, `LiveActivityManager`, and `DepartureReminderService`
are concrete `@Observable` classes with no protocol; test them via their
public interface.

---

## ATPClient — `Verkéier/Services/ATP/ATPClient.swift`

Live transit data from the mobiliteit.lu OpenAPI. Gated behind `ATP_ACCESS_ID`;
`EmptyATPClient` is used when the key is absent.

```swift
protocol ATPClient: Sendable {
    nonisolated func nearbyStops(latitude: Double, longitude: Double) async throws -> [Stop]
    nonisolated func departureBoard(stopId: String) async throws -> [Departure]
    nonisolated func departureBoards(stopIds: [String]) async throws -> [Departure]
    // default impl: normalises ids, queries each, merges via ATPMapper
}

enum ATPClientError: Error, Equatable {
    case missingAccessId
    case invalidResponse
    case httpStatus(Int)
    case allPlatformRequestsFailed
}
```

---

## GTFSService — `Verkéier/Services/GTFS/GTFSService.swift`

On-device GTFS lookups. All methods are non-throwing and work fully offline.
Production implementation: `LocalGTFSService`.

```swift
protocol GTFSService: Sendable {
    nonisolated func searchStops(query: String) async -> [Stop]
    nonisolated func stopsForMap(center: LocationPoint, latitudeDelta: Double,
                                 longitudeDelta: Double, limit: Int) async -> [Stop]
    nonisolated func stop(id: String) async -> Stop?
    nonisolated func allStops() async -> [Stop]
    nonisolated func routesForStop(id: String) async -> [TransitRoute]
    nonisolated func timetableIndex() async -> GTFSTimetableIndexPayload?
}
```

---

## AVLClient — `Verkéier/Services/AVL/AVLClient.swift`

Ville de Luxembourg disruption XML feed.

```swift
protocol AVLClient: Sendable {
    nonisolated func fetchMessages() async throws -> [AlertMessage]
}

enum AVLClientError: Error {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
}
```

---

## RouteService — `Verkéier/Services/Routing/RouteService.swift`

Journey planning and Apple Maps handoff.

```swift
protocol RouteService: Sendable {
    nonisolated func calculateRoute(
        from: LocationPoint, to: LocationPoint,
        time: RoutePlanningTime, filters: RoutePlannerFilters
    ) async throws -> RouteCalculation

    @MainActor func openInAppleMaps(from: LocationPoint, to: LocationPoint)
}

// Convenience default implementations (no filters / no time):
//   calculateRoute(from:to:)          → .leaveNow, default filters
//   calculateRoute(from:to:time:)     → default filters

enum RoutingError: Error, Equatable {
    case noRouteFound
    case timetableUnavailable
    case noPublicTransportRoute
}
```

`RouteCalculation` holds `options: [RouteOption]` and `selectedOptionID`.
`RouteOption` wraps a `RoutePlan` and computed properties: `transferCount`,
`walkingDistanceMeters`, `usesLiveData`, `status(at:)`.

`BikeShareService` provides vel’OH! static station data and on-demand dynamic
availability. The public-transport routing engine merges direct bike journeys
and bike rentals into walking gaps around transit legs. Bike legs carry pickup
and return station counts in `BikeShareLegDetails` so route cards, timelines,
and map annotations can show the same snapshot.

---

## GTFSUpdateError — `Verkéier/Services/GTFS/GTFSUpdateError.swift`

```swift
enum GTFSUpdateError: Error {
    case noGTFSResource
    case missingDownloadURL
    case serverError(Int)
    case downloadFailed
    case invalidArchive
    case unsupportedCompressionMethod(UInt16)
    case validationFailed(String)
}
```

---

## Domain model inventory — `Verkéier/Models/`

| Model | Purpose |
|---|---|
| `Stop` | Stop/station: id, name, locality, location, modes, platformIds |
| `Departure` | One departure row: lineName, destination, scheduled/realtime times, delayMinutes, isCancelled, platform |
| `TransitRoute` | A transit line: shortName, longName, mode, operatorName |
| `TransportMode` | `.train .tram .bus .funicular .walking .unknown` |
| `DataSource` | Provenance: `.atpOpenAPI .gtfs .avl .mapKit .local .mock` — carried on all models |
| `LocationPoint` | Codable lat/lon; convert to `CLLocationCoordinate2D` via `.coordinate` |
| `AlertMessage` | Disruption message with severity, affectedStopIds, affectedRouteIds |
| `FavouriteStop` | Persisted stop bookmark, denormalized at save time |
| `LineDetail` | Route detail from GTFS: stopSequence, upcomingDepartures, mapOverlay |
| `RouteOption` | `RoutePlan` + map overlay + derived UI properties |
| `RoutePlan` | Ordered legs (transit, walking) with scheduled and realtime times |
| `RouteMapOverlay` | Polyline segments + transfer markers for MapKit rendering |
| `RouteLoadingPhase` | `.idle .waitingForLocation .calculating` — drives progress UI |
| `DataReadinessSnapshot` | Per-source readiness summary for settings/debug UI |
| `RoutePlannerModels` | `RoutePlannerFilters`, `RoutePlanningTime`, `RoutePlace`, `RouteCommutePreset` |
