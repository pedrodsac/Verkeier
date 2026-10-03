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
When that generation changes, both are rebuilt. Find Routes, presets and new
searches reuse compatible fresh evidence; Refresh Routes bypasses completed
cache entries. Earlier/later pages retain fresh observations and acquire missing
coverage for new boarding occurrences. New evidence revalidates accumulated
results in the active generation before a complete snapshot is published.

Live acquisition uses at most four concurrent requests, four discovery waves,
24 stop targets, and one two-second budget. Reachability and effective boarding
times select per-stop windows for the current search or page, including legs
beyond the former 90-minute horizon. Adjacent windows merge into unrestricted
`maxJourneys=-1` requests rather than 50-journey slices. ATP's 1,439-minute limit
still applies. A trip prediction from another stop does not suppress checks for
an occurrence without fresh live timing. Failure, timeout, missing configuration
and ambiguous matches preserve valid scheduled results; completed evidence is
retained when later acquisition times out.

Realtime data is applied before RAPTOR selects a journey. Walking access,
boardability, transfers, dominance, arrival times, and route ordering therefore
use effective times. ATP passlists provide independent arrival and departure
predictions for each matched GTFS stop sequence, preserving delay recovery and
repeated stops. Reported predictions remain observed; missing predictions can
inherit an estimate forward for up to 30 minutes from a report (delay limited
to two hours). Earlier unobserved stops remain scheduled. Per-stop restrictions
prevent boarding or alighting without cancelling the whole vehicle.

Discovery prioritizes transfer stops with fewer remaining rides to the destination
and skips outgoing trips whose downstream stops cannot reach it. This prevents
earlier intermediate boards from exhausting the stop budget before later lines.
Discovery includes reachable transfer departures absent from static winners,
merges overlapping observations, then performs one final RAPTOR scan. The
optimistic discovery envelope advances one ride per wave, avoiding repeated
scans of all earlier waves. Matching
rejects ambiguous or non-monotonic active updates and counts rejection reasons.
The shared departure-board cache coalesces compatible overlapping requests,
permits independent cancellation, and fetches only uncovered intervals. Endpoint,
credentials, station, language, filters, realtime mode and passlist availability
isolate coverage; truncated boards cannot establish complete coverage. Routing
and stop boards use the app's configured language. Original acquisition dates
survive cache hits and gap assembly, with 60-second expiration and bounded
eviction. Older requests cannot overwrite refreshed coverage.

MobiliteitKit's additive `departureBoardSnapshot` API exposes the board,
acquisition timestamp, requested interval and completeness. The app maps each
row with its original observation timestamp and uses the snapshot date for
board freshness, including empty boards. The stop board retains its 1,439-minute
range and scheduled fallback on live failure. Metrics include board requests,
cache hits, bytes, incomplete coverage and matched event counts; the simulator
benchmark separately reports displayed-leg evidence and matching rejections.

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

## Live passlist routing verification

The passlist implementation passes 87 MobiliteitKit tests, including delayed
past departures, independently recovering arrivals/departures, transfers found
in later acquisition waves, skipped stops, repeated stop occurrences,
after-midnight service dates, DST transitions, ambiguous wall-clock rejection,
truncated boards, refresh, coalescing, cancellation and schedule-only fallback.
The app integration test verifies that reported downstream arrivals remain
observed through the presentation adapter. The relay passes its four offline
contract tests and TypeScript checks. Its deployed `passlist-v2` contract was
verified against ATP with a one-journey request returning one departure and
21 passlist stops; legacy `FULL` succeeds through translation and invalid modes
return 400.

`LiveRoutingBenchmark` is an opt-in Release scheme using the installed GTFS
feed and the recorded September 30 Esch departure fixture in
`VerkéierTests/Fixtures/`. It confirms that GTFS trip `24284828`, scheduled
before the 18:35 query anchor, remains selectable using its reported delay.
Run with code coverage disabled:

```sh
xcodebuild -project Verkeier.xcodeproj -scheme LiveRoutingBenchmark \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -enableCodeCoverage NO test \
  -only-testing:VerkeierTests/RecordedLiveRoutingBenchmarkTests
```

The simulator's installed feed must contain September 30, 2026 and that trip.
For a device run, replace the destination with its device ID and install a
compatible feed first. Normal app tests leave this benchmark disabled.

The September 30 iPhone 17 simulator sample measured:

| Run | Total engine time | Live acquisition | HTTP requests | Board cache hits |
|---|---:|---:|---:|---:|
| Cold, including snapshot | 14.48s | 0.99s | 72 | 0 |
| Warm | 14.64s | 0.89s | 0 | 24 |
| Explicit refresh | 13.82s | 0.89s | 72 | 0 |
| Schedule-only comparison | 13.11s | 0s | 0 | 0 |

Each live run used 24 stop targets with three 30-minute slices each. Coverage
was correctly partial. Carrying the discovery envelope forward reduced four
waves from ten reachability scans to four; the preceding replay's warm
acquisition took 2.17s. These are individual simulator samples with replayed
ATP data, not mobile-network or physical-device latency measurements. RAPTOR's
24-hour profile still accounts for roughly 13 seconds on this route; this work
reduces live acquisition cost without claiming instant full-route results.
Device execution was deferred at the user's request after Xcode reported the
connected iPhone locked.
