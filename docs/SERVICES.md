# Services

Service protocols live in `Verkéier/Services/`. The current Swift declarations
are the contract; this document explains how they fit together. Views receive
services through `@Environment`, with entries in
`Verkéier/App/AppDependencies.swift`. `VerkéierApp` supplies the live
implementations. Previews and tests can inject fixture or unavailable services.

```swift
@Environment(\.liveTransitService) private var liveTransitService
@Environment(\.gtfsService) private var gtfsService
```

| Protocol | Production implementation | Fixture or fallback |
|---|---|---|
| `LiveTransitService` | `MobiliteitLiveTransitService` | `FixtureLiveTransitService`, `UnavailableLiveTransitService` |
| `GTFSService` | `MobiliteitGTFSService` | `FixtureGTFSService`, `UnavailableGTFSService` |
| `AVLClient` | `LiveAVLClient` | `MockAVLClient`, `EmptyAVLClient` |
| `RouteService` | `MobiliteitRouteService` | `MapKitRouteService` (unavailable calculation; Apple Maps handoff only) |
| `BikeShareService` | `JCDecauxBikeShareService` | `UnavailableBikeShareService` |

## Live transit

`Verkéier/Services/Transit/LiveTransitService.swift` provides nearby stops and
filtered departure boards. `MobiliteitLiveTransitService` uses MobiliteitKit
for typed HAFAS requests through `API_PROXY_URL/atp`; it sends no ATP key in
the app. Without a relay URL, live transit reports `notConfigured`. The
routing service shares its realtime client.

## GTFS

`Verkéier/Services/Transit/GTFSService.swift` provides stop search, schedules,
route shapes, and routing data. `MobiliteitGTFSService` discovers and downloads
the current official GTFS archive, validates and installs it, and keeps the
last usable timetable if a refresh fails. Calls return app domain models and
work offline once a valid database has been installed.

## AVL

`Verkéier/Services/AVL/AVLClient.swift` fetches Ville de Luxembourg disruption
messages from the configured public XML feed.

## Route planning

`Verkéier/Services/Routing/RouteService.swift` defines journey calculation,
streamed updates, and Apple Maps handoff. `MobiliteitRouteService` uses the
local GTFS database with optional HAFAS realtime overlays. Walking routes use
the local pedestrian graph exclusively. Missing graphs report walking as unavailable.

`RouteCalculation` holds `options: [RouteOption]` and `selectedOptionID`.
`RouteOption` wraps a `RoutePlan` and computed properties: `transferCount`,
`walkingDistanceMeters`, `usesLiveData`, `realtimeCoverage`, `status(at:)`.

Route generation accepts a departure instant or an arrival deadline. A result
must include its access walk after the departure instant or finish its egress
walk by the deadline. The router searches up to three transfers by default,
retains time, walking, and transfer tradeoffs, and returns up to five transit
alternatives plus a separate direct walking comparison. The first visible
option is chronological; `selectedOptionID` carries the recommended choice.
Paging uses a departure-time and stable-journey-ID cursor so equal-time options
are not skipped. The supported arrival profile covers the previous 24 hours;
the forward profile is bounded and does not imply exhaustive network coverage.

The planner's mode control is a soft preference; package `allowedModes` is a
separate hard filter. Walking legs retain routed-versus-estimated evidence
through the app model; an estimated interchange cannot
prove a transfer catchable. A local graph's explicit `noRoute` result is kept
as unreachable; missing or unusable graphs report walking as unavailable. Walking refinement validates the
original time constraint and transfer allowances; infeasible options are
invalidated and one corrected-cost replan is attempted.

MobiliteitKit’s `JourneyPlanner` keeps a `TransitRouter` and
`HafasRealtimeRoutingProvider` paired to the active GTFS database generation.
When that generation changes, both are rebuilt. A new calculation or explicit
refresh bypasses the 60-second HAFAS board cache; earlier/later paging reuses
covered snapshots. Live acquisition is capped at 32 concurrent board
requests and a four-second deadline within the route calculation's overall
15-second UI deadline. Failure, timeout, missing proxy configuration, and
ambiguous HAFAS-to-GTFS matches all preserve valid schedule-only results.

Realtime data is applied before RAPTOR selects a journey. Walking access,
boardability, transfers, dominance, arrival times, and route ordering therefore
use effective times. Reported boarding predictions remain observed, while a
known delay propagated to later vehicle stops is marked estimated.

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

## Route calculation ownership

MobiliteitKit owns transit search, prepared-router caching, request/page policy,
accumulated journey results, ranking and deduplication, transit polylines, feasibility,
route status and replacement planning after walking corrections. Verkéier renders
`JourneyPlanningResult` snapshots through `MobiliteitRouteService`; it preserves a
selectable manual choice or uses the package recommendation.

Verkéier retains GTFS installation, pedestrian routing exclusively with the local Valhalla graph, walking calibration, refinement requests and walking timing adjustments.
`AppJourneySessionStore` bridges refined native walking spans back to the package
session. UI loading deadlines, reveal timing, labels, overlays and Apple Maps handoff
remain in the app. Package refinement tokens prevent old queries from changing newer
results, and the package limits corrected-cache replacement searches to one per
planning generation.

## Ownership migration verification

The migration passes 71 MobiliteitKit tests and the full iPhone 17 simulator
suite, including app-to-package refinement feedback, snapshot mapping, manual
selection, cancellation, loading deadlines and local graph availability.

The existing Release route benchmark was compared using the same cached GTFS
feed, bundled pedestrian graph, simulator and fixed realtime provider. Cold
reverse address routing measured 14.00s before and 13.52s after; two warm
forward runs averaged 9.96s before and 9.81s after. This sample shows no material
latency regression. The earlier app's additional filtering changed its visible
result count; the new app passes the package alternatives through unchanged.
