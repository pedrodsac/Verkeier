# Verkéier

A native SwiftUI app for Luxembourg public transport, built to feel like Apple Maps.

## Overview

Verkéier presents a full-screen MapKit map with a persistent draggable bottom
sheet. It surfaces nearby stops, live departure boards, route planning,
disruption alerts, and offline timetables for Luxembourg's free public transport
network.

The codebase follows a strict, top-to-bottom layering that is never
short-circuited:

```
SwiftUI View → ViewModel/Observable State → Service Protocol → API Client/Storage → Decoder/Mapper → Domain Model
```

Networking and business logic never live in views. Everything is routed through
view models and injected services. Every service is expressed as a protocol with
multiple implementations — `Live*` for production, `*Mock`/`Empty*` for
previews and tests, and often `Local*` for on-device data. Dependencies are
injected through SwiftUI's environment via `@Entry` (the `EnvironmentValues`
extension in `AppDependencies.swift`), so previews and tests can override any
service with a mock.

## Topics

### Domain Models

The typed value models that flow through every layer. These are `Sendable`
value types, decoded and mapped from external feeds before they reach the UI.

- ``Stop``
- ``Departure``
- ``DepartureStatus``
- ``TransitRoute``
- ``TransportMode``
- ``LineDetail``
- ``AlertMessage``
- ``FavouriteStop``
- ``LocationPoint``
- ``DataSource``

### Route Planning Models

- ``RoutePlan``
- ``RouteOption``
- ``RouteOptionStatus``
- ``RouteMapOverlay``
- ``RoutePlace``
- ``RouteCommutePreset``
- ``RoutePlannerFilters``
- ``RouteLoadingPhase``

### Data Readiness

- ``DataReadinessSnapshot``
- ``DataReadinessItem``

### Service Protocols

Each protocol is the seam between the UI and a data source. Pick an
implementation by injecting it into the environment.

- ``AVLClient``
- ``RouteService``

### Service Implementations

- ``DepartureReminderService``
- ``LocationService``
