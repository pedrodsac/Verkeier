# LuxTransit PRD

## Product Summary

LuxTransit is a native iOS app for Luxembourg public transport. It provides a map-first interface for nearby stops, live departures, delay awareness, favourites, route handoff, alerts, Live Activities, App Intents, and widgets.

The app is not official and must not imply endorsement by Administration des transports publics, Ville de Luxembourg, mobiliteit.lu, AVL, Luxtram, or Apple.

## Goals

- Make nearby public transport information available from a full-screen map.
- Show live departure information with clear delay, cancellation, stale, loading, empty, and error states.
- Let users save favourite stops locally.
- Provide route planning through MapKit where feasible and Apple Maps handoff as the reliable fallback.
- Surface selected departure tracking through Live Activities.
- Expose useful system actions through App Intents.
- Provide widgets that are honest about refresh limits and do not pretend to be continuously live.
- Include attribution, privacy, location usage, diagnostics, and support information.

## Non-Goals

- Do not create accounts, ads, subscriptions, or a backend service.
- Do not claim to be an official transit app.
- Do not hardcode API keys.
- Do not implement full GTFS journey planning in the MVP.
- Do not claim WidgetKit widgets are live real-time surfaces.
- Do not invent live data or statuses when a source does not provide them.

## Primary User Experience

The first screen is a full-screen Apple Maps-style map centered on Luxembourg City or the user's current location when permission is granted. Stops are displayed as map annotations. A persistent draggable bottom sheet sits over the map and contains the app's main workflows.

The bottom sheet uses a compact contextual header with a section menu, not a large top action rail. Main sections are:

- Nearby
- Search
- Stop
- Route
- Favourites
- Alerts
- Settings

## Core Workflows

### Nearby Stops

- Request location permission when needed.
- Load nearby stops from ATP mobiliteit.lu OpenAPI when an access ID is configured.
- Fall back to mock fixtures when no ATP access ID is configured.
- Show loading, error, and empty states.
- Selecting a stop centers the map and opens stop details.

### Live Departures

- Show line, destination, scheduled/realtime departure, delay, cancellation, platform, operator when available, and last updated time.
- Display stale state when departure data is old.
- Support manual refresh and active-screen automatic refresh.

### Search

- Search cached or generated GTFS stop data fetched from the configured service.
- Search must be accent-tolerant.
- Selecting a search result centers the map and opens stop details.

### Favourites

- Save and remove favourite stops.
- Persist favourites locally with SwiftData.
- Mirror favourite stop display data to shared storage for widgets and App Intents.
- Show favourite markers on the map.

### Routing

- Calculate a MapKit route from current location to selected stop where feasible.
- Always offer Apple Maps transit handoff.
- MapKit is the routing/map layer; ATP is not treated as a route-planning source.

### AVL Alerts

- Fetch Ville de Luxembourg AVL messages XML.
- Parse message ID, title, body, category, urgency, start/end dates, affected lines, and affected stops.
- Show malformed, empty, loading, stale, and error states safely.

### Live Activities

- Allow manually tracking a selected departure.
- Show line, destination, stop, countdown/status, delay/cancellation, and last updated/stale state.
- Use local/app-driven updates only. No backend push in MVP.

### App Intents

Expose:

- Show nearby stops
- Open favourite stop
- Track next departure
- Plan route
- Get next departures

Favourite stops are exposed as App Entities.

### Widgets

Feasible MVP widgets:

- Small favourite stop widget
- Medium departures launcher widget
- Lock-screen / Dynamic Island Live Activity countdown

Widgets must communicate that live departures require opening the app unless a Live Activity is actively tracking a departure.

### Settings, Attribution, Privacy

Settings must include:

- Data-source attribution
- Privacy explanation
- Location usage explanation
- API diagnostics
- App version/support placeholder

Attribution placeholder:

```text
Transport data:
Administration des transports publics - mobiliteit.lu OpenAPI
Administration des transports publics - GTFS public transport schedules and stops
Ville de Luxembourg - AVL Autobus

Maps:
Apple Maps / MapKit
```

Exact production wording must be confirmed before release.

## Data Sources

### ATP mobiliteit.lu OpenAPI

Used for nearby stops and realtime departures. Requires `ATP_ACCESS_ID`, which must not be committed. Missing access ID must be handled gracefully through mocks.

### GTFS

Used for local static stop search and future route/line metadata. MVP uses local sample/preprocessed data.

### Ville de Luxembourg AVL

Used for public bus/tram traffic messages. MVP uses the public XML messages feed and maps general alerts first.

### MapKit / Apple Maps

Used for map display, user location, route display, and Apple Maps transit handoff.

## Quality Requirements

- Native SwiftUI, MapKit, Core Location, SwiftData, ActivityKit, App Intents, WidgetKit.
- Async/await service boundaries.
- Dependency injection for live/mock services.
- No networking in SwiftUI views.
- No business logic in view bodies.
- Testable decoders/mappers/parsers.
- Build after each phase.
- Support light/dark mode, Dynamic Type, and VoiceOver basics.
