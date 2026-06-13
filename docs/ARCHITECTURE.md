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
LuxTransit/
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
func nearbyStops(latitude: Double, longitude: Double) async throws -> [Stop]
func departureBoard(stopId: String) async throws -> [Departure]
```

### GTFSService

```swift
func searchStops(query: String) -> [Stop]
func stop(id: String) -> Stop?
func routesForStop(id: String) -> [TransitRoute]
```

### AVLClient

```swift
func fetchMessages() async throws -> [AlertMessage]
```

### MapKitRouteService

```swift
func calculateRoute(from: LocationPoint, to: LocationPoint) async throws -> RoutePlan
func openInAppleMaps(from: LocationPoint, to: LocationPoint)
```

### LiveActivityManager

```swift
func startTracking(departure: Departure, stop: Stop) async throws
func updateTracking(departure: Departure) async
func endTracking()
```
