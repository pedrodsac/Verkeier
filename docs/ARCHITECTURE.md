# Architecture

## Goal

Create a serious native iOS codebase for a Luxembourg public transport app.

The app should feel like Apple Maps:

- full-screen MapKit map
- persistent draggable bottom sheet
- controls, search, stops, departures, route planning, favourites, and alerts inside the sheet
- smooth native interactions
- light/dark mode
- accessibility support

## Stack

Use:

- SwiftUI
- MapKit
- Core Location
- SwiftData
- ActivityKit
- App Intents
- WidgetKit
- async/await
- URLSession
- local fixtures/mocks for development

## High-Level Pattern

```text
SwiftUI View
→ ViewModel / Observable State
→ Service Protocol
→ API Client / Storage Layer
→ Decoder / Mapper
→ Domain Model
```

Rules:

- no networking in views
- no business logic in view bodies
- no massive `ContentView.swift`
- no hardcoded fake production data
- no god view models
- UI must be previewable with mock data
- API/parsing code must be testable without UI

## Main Modules

```text
Verkéier/
├── App/
├── Features/
│   ├── Map/
│   ├── BottomSheet/
│   ├── Stops/
│   ├── Departures/
│   ├── Search/
│   ├── Routes/
│   ├── Favourites/
│   ├── Alerts/
│   ├── Settings/
│   ├── LiveActivities/
│   ├── AppIntents/
│   └── Widgets/
├── Services/
│   ├── ATP/
│   ├── GTFS/
│   ├── AVL/
│   ├── Location/
│   ├── Routing/
│   └── Cache/
├── Models/
├── Storage/
├── Networking/
├── Utilities/
├── Resources/
├── Tests/
└── docs/
```

## Core Services

### ATPClient

```swift
nonisolated func nearbyStops(latitude: Double, longitude: Double) async throws -> [Stop]
nonisolated func departureBoard(stopId: String) async throws -> [Departure]
nonisolated func departureBoards(stopIds: [String]) async throws -> [Departure]
```

### GTFSService

```swift
nonisolated func searchStops(query: String) async -> [Stop]
nonisolated func stopsForMap(center: LocationPoint, latitudeDelta: Double, longitudeDelta: Double, limit: Int) async -> [Stop]
nonisolated func stop(id: String) async -> Stop?
nonisolated func allStops() async -> [Stop]
nonisolated func routesForStop(id: String) async -> [TransitRoute]
nonisolated func timetableIndex() async -> GTFSTimetableIndexPayload?
```

### AVLClient

```swift
nonisolated func fetchMessages() async throws -> [AlertMessage]
```

### RouteService

```swift
nonisolated func calculateRoute(from: LocationPoint, to: LocationPoint, time: RoutePlanningTime, filters: RoutePlannerFilters) async throws -> RouteCalculation
@MainActor func openInAppleMaps(from: LocationPoint, to: LocationPoint)
```

### LiveActivityManager

```swift
func startTracking(departure: Departure, stop: Stop) async throws
func updateTracking(departure: Departure) async
func endTracking()
```

## Dependency Injection

Services are injected via SwiftUI `EnvironmentValues` using `@Entry`
(Swift 5.10+). All entries are declared in `Verkéier/App/AppDependencies.swift`.

```swift
// Read in any view:
@Environment(\.atpClient) private var atpClient

// Override in a preview:
#Preview {
    MyView().environment(\.atpClient, ATPMockClient())
}
```

The app entry point (`VerkéierApp`) wires live implementations at launch.
Default values in `AppDependencies.swift` are the safe no-op stubs
(`EmptyATPClient`, `LocalGTFSService`). See `docs/SERVICES.md` for all
protocol signatures and mock implementations.

## Domain Model Inventory

15 model files in `Verkéier/Models/`. Key ones:

- **Stop** — canonical place: id, name, locality, location, modes, platformIds
- **Departure** — one departure row; scheduled/realtime times, delayMinutes, isCancelled
- **TransitRoute** — a transit line: shortName, mode, operatorName
- **RoutePlan** / **RouteOption** — journey result with legs, overlays, and live-status
- **LocationPoint** — Codable lat/lon coordinate; convert with `.coordinate`
- **DataSource** — provenance enum on all models: `.atpOpenAPI .gtfs .avl .mock …`

Full signatures and all 15 models: `docs/SERVICES.md`.
