# MVP Checklist

Build in phases. Each phase must compile before moving on.

## Phase 1 — Project Baseline

- verify/create SwiftUI iOS app target
- create clean folder structure
- add app entry point
- add placeholder environment/config system
- add README setup instructions
- add ignored local secrets/config example
- confirm `docs/PRD.md` exists
- build successfully

## Phase 2 — Map-First Shell

- full-screen MapKit map
- user location permission handling
- map camera state
- persistent Apple Maps-style draggable bottom sheet
- sheet detents: collapsed, medium, expanded
- sheet modes: nearby, search, stop, route, favourites, alerts
- placeholder content for each mode
- map remains visible behind the sheet
- build successfully

## Phase 3 — Core Models

Add:

- `Stop`
- `Departure`
- `FavouriteStop`
- `AlertMessage`
- `TransitRoute`
- `TransportMode`
- `DataSource`
- `LocationPoint`
- `RoutePlan`

Departure status rules:

- missing real-time value → Scheduled
- delay = 0 → On time
- delay > 0 → +X min
- cancelled → Cancelled
- unknown → Unknown

Add tests for delay/status logic.

## Phase 4 — ATP Client

- `nearbyStops`
- `departureBoard`
- no hardcoded API key
- mock fixtures
- decoding/mapping layer
- loading/error/empty handling
- tests where practical

## Phase 5 — Nearby Stops and Markers

- location-based stop loading
- stop markers on map
- selected stop state
- marker tap opens bottom sheet stop detail
- nearby stop list
- mock data support

## Phase 6 — Live Departures

- stop detail board
- line, destination, scheduled time, real-time time, delay
- cancellation/platform/operator if available
- manual refresh
- short active-screen auto refresh
- stale data state

## Phase 7 — GTFS Search

- local stop search
- accent-tolerant search
- sample/preprocessed stop database
- selecting stop centers map and opens detail

## Phase 8 — Favourites

- save/remove favourite stop
- local persistence
- favourites panel
- favourite map marker state

## Phase 9 — MapKit Routing

- route planning UI
- current location / selected stop / searched destination
- MapKit route if feasible
- Apple Maps transit handoff fallback

## Phase 10 — AVL Alerts

- fetch/parse AVL messages
- cache briefly
- alerts panel
- safe handling of malformed/empty XML

## Phase 11 — Live Activities

- manually track a selected departure
- line, destination, stop, countdown, delay, cancellation, last updated
- short-lived local/app-driven updates
- stale-state warning
- no backend push unless explicitly requested

## Phase 12 — App Intents

Add intents for:

- get next departures
- open favourite stop
- track next departure
- plan route
- show nearby stops

Expose favourite stops as App Entities.

## Phase 13 — Widgets

If feasible:

- small favourite stop widget
- medium departures widget
- lock-screen countdown widget

Widgets must not pretend to be continuously live.

## Phase 14 — Settings / Attribution / Privacy

- settings screen
- attribution/legal screen
- privacy explanation
- location usage explanation
- API diagnostics
- app version/support placeholder

Attribution placeholder:

```text
Transport data:
Administration des transports publics — mobiliteit.lu OpenAPI
Administration des transports publics — GTFS public transport schedules and stops
Ville de Luxembourg — AVL Autobus

Maps:
Apple Maps / MapKit
```

Replace with exact wording after ATP confirmation.
