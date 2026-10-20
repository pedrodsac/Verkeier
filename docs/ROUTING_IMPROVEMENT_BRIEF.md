---
doc: routing-improvement-brief
audience: AI coding agents asked to make route calculation faster or better
written: 2026-10-15
app: Verkeier @ refactor/views-and-structure 9110b4a
engine: MobilitéitKit @ c4f4b70729971d0c17bd0e8c4b238f6b57a1e3df (pinned in Package.resolved)
feed: GTFS generation 6, service 2026-10-14..2026-12-12
walking_graph: Valhalla tiles 20260921
baseline_benchmark: docs/benchmarks/live-baseline-2026-10-15/
---

# Routing improvement brief

This document describes how Verkéier calculates a public-transport route, what a
live search currently costs, and where improvements are likely. It is written for
an agent that will propose and implement changes. Source code is the authority;
if this document and the code disagree, trust the code and update this file.

## 0. How to use this document

1. Read §1 (invariants) before touching anything. A faster router that breaks one
   of them is a regression.
2. Use §2–§8 as a map: every step names its file and symbol; §8 lists the constants.
3. Read §9 (live baseline benchmark) and §10 (past experiments) to see where time
   goes and what has already been tried.
4. Pick from §11 (candidate improvements) or propose new ones in the same format.
   §13 suggests an order.
5. Measure with §12. Report before/after numbers *and* result equality.

Identifiers are stable so you can refer to them: `INV-n` invariants, `ST-n`
pipeline stages, `C-n` constants, `EXP-n` past experiments, `CAND-n` candidates.

Path prefixes:

| Prefix | Meaning |
|---|---|
| `app:` | This repository, `Verkéier/` |
| `kit:` | Sibling checkout `../MobilitéitKit/Sources/MobilitéitKit/` (the engine) |
| `docs:` | This repository, `docs/` |

The engine lives in a separate Swift package. The app pins it by revision, so an
engine change needs: commit in MobilitéitKit → push → update the app's
`Package.resolved` pin. Test the engine there with
`ROUTING_VERIFY_KERNEL=1 swift test --no-parallel` (parallel runs of the
realtime/HTTP mock suites are flaky).

---

## 1. Invariants (must not break)

| ID | Rule | Source |
|---|---|---|
| INV-1 | **Performance changes must not change results.** Compare canonical plans / journey hashes before and after on identical inputs (recorded transport, fixed planning time). Timing alone is not evidence. | `Scripts/compare_route_benchmarks.py`, `docs:benchmarks/transfer-walks-2026-10-14/README.md` |
| INV-2 | Never publish an invalid journey: every trip instance exists and runs that day, boarding position < alighting position, pickup/drop-off permitted, legs chronological and physically connected, no trip instance used twice. | `kit:Routing/JourneyStructuralValidator.swift`, `kit:Routing/JourneyFeedValidator.swift` |
| INV-3 | Transfer minima are **totals including walking**. Required wait after walking = `max(boardingBuffer, total − walking)`, rounded up. Zero shortfall: negative slack is never selectable. | `kit:Routing/JourneyTransferArithmetic.swift`, `docs:ROUTING_FAILURE_PREVENTION_PLAN.md` §Transfer arithmetic |
| INV-4 | **Preserve future eligibility when pruning labels.** A label may only be discarded if no later round could have used it. Classic target pruning was tried and rejected for this reason (EXP-3). | `docs:ROUTING_FAILURE_PREVENTION_PLAN.md` B.6 |
| INV-5 | Live data: an *estimated* departure is uncertain, so the boarding deadline is `min(scheduled, estimate)`. Missing live data is never a cancellation. A cancellation is authoritative for the whole vehicle instance. Observations older than 120 s are not used as live. | `kit:Routing/RaptorPreparationCache.swift`, `kit:Routing/RealtimeTimeline.swift` |
| INV-6 | Do not shrink product budgets without the owner agreeing: 8 s live acquisition, ≤3 transfers, 48-label profiles, 2 h→24 h window expansion, live checks on every selected vehicle. Previous performance work kept these fixed ("exact-equivalence contract"). | `docs:ROUTE_CALCULATION_PERFORMANCE.md` |
| INV-7 | Deterministic output: chunk merge order, label IDs and tie-breaks must not depend on thread timing. | `kit:Routing/RaptorPatternMerge.swift` |
| INV-8 | The compact kernel and the reference kernel must stay equivalent. Any change to label state, dominance or eviction updates both. `ROUTING_VERIFY_KERNEL=1` must pass. | `kit:Routing/RaptorCompactScan.swift`, `kit:Routing/RaptorReferenceScan.swift` |
| INV-9 | Stay-seated continuations only from an explicit `transfer_type = 4` or the unique next trip of an unambiguous `block_id`. Same line number alone never fuses trips. | `kit:Routing/RaptorBlockContinuations.swift` |
| INV-10 | Project rules from `AGENTS.md`: layering (no networking/logic in views), Swift Testing only, no live network in tests, no hard-coded keys or dated GTFS URLs, files under ~400 lines, small focused commits. | `AGENTS.md` |
| INV-11 | Release rendered-result gate: every operation under 5,000 ms (simulator, Release, `ENABLE_CODE_COVERAGE=NO`). | `docs:ROUTE_CALCULATION_PERFORMANCE.md` |

---

## 2. System map

| Responsibility | Type | File |
|---|---|---|
| UI state, 15 s first-result deadline, merging, paging, refinement scheduling | `RoutePlannerModel` | `app:Features/Routes/Models/RoutePlannerModel+Calculation.swift`, `+Paging.swift`, `+Refinement.swift`, `+Realtime.swift` |
| Adapter: request building, error mapping, `Journey` → `RouteOption` | `MobiliteitRouteService` | `app:Services/Routing/MobiliteitRouteService.swift` |
| One engine session per request; concurrent bike-share branch | `AppJourneySessionStore` | `app:Services/Routing/AppJourneySessionStore.swift` |
| Bike share (vel'OH!) alternative | `BikeShareRoutePlanner` | `app:Services/Routing/BikeShareRoutePlanner.swift` |
| Router cache per database file | `JourneyPlanner` | `kit:Routing/JourneyPlanner.swift` |
| Accumulated pages, publication, validation, recommendation | `JourneyResultSession` | `kit:Routing/JourneyResultSession.swift` |
| In-memory timetable snapshot + one query's profile generation | `TransitRouter`, `JourneyPlanningSession`, `SnapshotBuilder` | `kit:Routing/TransitRouter.swift` |
| RAPTOR kernel | `enum Raptor` | `kit:Routing/Raptor*.swift` (hot loop `RaptorCompactScan.swift`) |
| Ranking and suggestion policy | `JourneyQualityPolicy` | `kit:Routing/JourneyQualityPolicy.swift`, `JourneyQualityEnvelope.swift`, `JourneySuggestionPolicy.swift`, `JourneyRedundantTransferPolicy.swift` |
| Live data acquisition and matching | `HafasRealtimeRoutingProvider` | `kit:Routing/HafasRealtimeRoutingProvider*.swift`, `JourneyPlanningSession+*Realtime*.swift`, `RealtimeTimeline.swift` |
| Walking routes | `LocalFirstWalkingRouter` → `ValhallaWalkingRouter` | `app:Services/Routing/LocalFirstWalkingRouter.swift`, `ValhallaWalkingRouter.swift` |
| Stored transfer walks | `TransferWalkTable`, `TransferWalkStore` | `app:Services/Routing/TransferWalks/`, `docs:TRANSFER_WALKS.md` |
| GTFS import | `GTFSArchiveInstaller` | `kit:GTFSArchiveInstaller.swift`, `kit:GTFSImportIntegrity.swift` |
| Diagnostics (stage timings, counters, passes, rounds) | `RoutingDiagnostics` | `kit:Routing/RoutingDiagnostics.swift` |
| Benchmark harness | `SimulatorRouteBenchmark` | `app:App/Benchmarks/SimulatorRouteBenchmark.swift`, `Scripts/benchmark_routes.py` |

### 2.1 Data profile (installed feed, generation 6)

| Item | Count |
|---|---:|
| Stops (all `location_type = 0`; no stations, no `parent_station`, no `platform_code`) | 2,805 |
| Routes (709 bus, 5 rail, 1 tram) | 715 |
| Trips | 28,006 |
| Stop times (≈22.9 per trip) | 641,398 |
| RAPTOR patterns (route + exact stop sequence) | 1,748 |
| Transfer rules: all same-stop; 2,668 type 2, 236 type 1; 213 route/trip scoped | 2,904 |
| Stops with at least one transfer rule | 2,691 (96 %) |
| `min_transfer_time` values: 300 s ×2,657, 180 ×4, 120 ×3, 60 ×3, 450 ×1 | |
| Trips with `block_id` | 2,660 |
| Pathways, frequencies | 0, 0 |
| Max service time | 102,030 s (28:20:30) |
| Directed transfer-walk pairs | ≈11,188 |

Consequences: station-group logic and pathway relaxation are no-ops on this feed;
the funicular exists only as a walking connection (no GTFS route type 7);
almost every same-stop bus change hits a 300 s feed rule that the bus exception
(§5.4) lowers to 120 s.

---

## 3. Offline preparation

### 3.1 GTFS import (`kit:GTFSArchiveInstaller.swift`)
- Source: data.public.lu dataset catalogue (`app:Services/Transit/MobiliteitGTFSService.swift`); each install is a new generation file.
- Streaming CSV → temporary SQLite (journal off) → integrity checks (`validateRoutingIntegrity`: strictly increasing `stop_sequence`, non-negative non-decreasing times, positive pathway times, non-negative `min_transfer_time`) → materialise `service_date(day_index, service_id)` → indexes → atomic replace.

### 3.2 Routing snapshot (`kit:Routing/TransitRouter.swift` `SnapshotBuilder.load`)
Built once per database file (`JourneyPlanner.router(for:)`, keyed by path + size + mtime). Loaded **from SQLite on every process start**.
- One ordered scan of all stop times. Trips with <2 stop times or invalid timelines are quarantined (`TripTimeline.isValid`).
- `frequencies.txt` with `exact_times = 1` expanded to `trip#frequency-<start>` trips.
- Boardable stops (`pickup_type = 0` with a departure), alightable stops (`drop_off_type = 0` with an arrival).
- Patterns = route + exact ordered stop list (`SnapshotPatternGrouping`).
- Per-day active service sets; conversion `local noon − 12 h + seconds` (agency time zone, default `Europe/Luxembourg`).
- Transfer rules grouped by `(from station group, to station group)`.
- `nearbyTransferStopsByStop`: grid 0.005°, ±3 cells; ≤8 stops within 450 m (one per station group first); if <3 groups, add up to 12 within 900 m. Only for alightable sources.
- `SnapshotContinuationIndex`: block groups, explicit type-4 links, reverse edges for pruning.

### 3.3 Walking
- Valhalla pedestrian costing on bundled OSM tiles; pool of up to 4 native routers (`LocalFirstWalkingRouter.withLocalRouter`).
- Every duration × **1.25** (`WalkingDurationCalibration`).
- RAPTOR batch path uses `ShortWalkingRouteSearch`: `minimumReachability = 0`, retried with 50 if it fails or exceeds 1.5 km / 15 min.
- Pafendall funicular (`app:Services/Routing/PafendallFunicularConnection.swift`): tram stop (≤120 m) ↔ rail stop (≤100 m) → walk + 63 s ride + 60 s boarding + walk, used if faster than the direct walk.
- Caches: app `MeasuredWalkingRouteCache` (8,192, coordinate + graph revision); engine `WalkingRouteCache` (16,384; departure-independent; `correct()` overrides).
- Stored transfer walks: ≈11,188 pairs precomputed at launch into a 6 MB memory-mapped table (`docs:TRANSFER_WALKS.md`). Results identical; removes cold-process Valhalla work.

---

## 4. Request pipeline

Stage IDs map to `RoutingDiagnostics.Stage` names (the benchmark's `stages_ms`).
Stage durations are **wall-clock spans summed per stage**; spans overlap (for
example `realtime` runs alongside `walkingPreparation`, and `raptor` contains
`walkingTransfers`), so the sum of stages exceeds `total_ms`. `http` and `decode`
are cumulative work across concurrent requests.

| ID | Stage (`stages_ms` key) | What happens | Where |
|---|---|---|---|
| ST-1 | `timetableReadiness` | Find installed GTFS generation or trigger a refresh | `MobiliteitRouteService.readyDatabaseURL` |
| ST-2 | `snapshotPreparation` | Get/build the `TransitRouter` (cold: `SnapshotBuilder.load`) | `JourneyPlanner.router(for:)` |
| ST-3 | `graphPreparation` | Wait for walking graph, `checkAvailability` | `MobiliteitRouteService.calculateRoute` |
| ST-4 | `bikeCalculation` | vel'OH! option, concurrent with transit | `AppJourneySessionStore.measuredBike` |
| ST-5 | `endpoints` | Access/egress stop candidates + routed walks (once per session) | `JourneyPlanningSession.endpointEdges` |
| ST-6 | `realtime` (+ `realtimeDiscovery`, `boardFetch`, `schedulePreparation`, `boardMatching`, `http`, `decode`) | Live board acquisition and matching | §6 |
| ST-7 | `walkingPreparation` | Schedule-only warm-up RAPTOR during acquisition (never published) | `prepareWalkingWhileAcquiring` |
| ST-8 | `raptor` (+ `walkingTransfers`) | Authoritative RAPTOR scans (≤3 per window) | `Raptor.search` |
| ST-9 | `candidateBuilding` | Candidates → validated, deduplicated `Journey`s | `JourneyPlanningSession.buildJourneys` |
| ST-10 | `directWalkingWait` | Await the direct-walk comparison | `JourneyPlanningSession.directWalk` |
| ST-11 | `geometry` | Slice shapes for each ride | `JourneyGeometry.enrich` |
| ST-12 | `validation`, `ranking`, `resultAssembly` | Accumulated-result checks, filters, recommendation | `JourneyResultSession.snapshot` |
| ST-13 | `adapterMapping` | `Journey` → `RouteOption` | `MobiliteitRouteService.option` |
| ST-14 | `publication`, `firstRender` | Model publish → sheet rendered | `RoutePlannerModel.recordRoutePublication`, `recordRouteResultsRendered` |
| ST-15 | `refinement` | After render: re-route walks, submit to engine | `RoutePlannerModel+Refinement.swift` |

### 4.1 Control flow of one initial search

```
RoutePlannerModel.calculateRoute                          (15 s deadline to first update)
└ MobiliteitRouteService.calculateRoute                   ST-1..ST-3
  └ AppJourneySessionStore.calculate                      ST-4 in parallel
    └ JourneyResultSession.calculate(.initial)            anchor = now for "leave now"
      └ JourneyPlanningSession.initialSuggestions(count: 6, horizon: 2 h)
          [if depart-after, live on, straight line ≥ 40 km: schedule-only pre-pass doubling 2 h→24 h until 7 suggestions]
          loop horizon = 2, 4, 8, 16, 24 h:
            generate(horizon)                              ← one "pass group"
            stop when primarySuggestions == 6 (depart) or ArrivalSearchStoppingPolicy (arrive-by)
      └ JourneyGeometry.enrich, merge, snapshot()         ST-11, ST-12
  └ calculation(from:) mapping                            ST-13
RoutePlannerModel.applyRouteOptions → render              ST-14
scheduleWalkingRouteRefinement                            ST-15
```

### 4.2 `generate(horizon)` (`kit:Routing/TransitRouter.swift`)

1. Endpoint edges (cached for the session).
2. Seed live patches from earlier evidence, keeping only observations < 60 s old (skipped on forced refresh).
3. Start direct walk in background.
4. If live budget > 0, concurrently:
   - **discovery acquisition** (§6.2) on up to 32 shared board permits;
   - **warm-up RAPTOR** (schedule + seeds), then speculative live completion of its top picks with ≤4 requests.
5. Authoritative `Raptor.search` with the acquired overlay.
6. `buildJourneys`.
7. Up to **2 completion waves**: fetch boards for vehicles in the current top 6. If routing inputs changed (`routingEffectChanged`: status, effective times, deadlines, boarding/alighting permissions) → rescan; if only platforms/freshness changed → rebuild journeys without rescanning.

Worst case per `generate`: 1 warm-up + 3 authoritative scans. Window doubling repeats `generate` (later passes reuse live data and spend only the remaining budget).

---

## 5. RAPTOR kernel

### 5.1 Variant
- Rounds = vehicle rides; `maxRounds = maxTransfers + 1 = 4`.
- Each stop keeps a **profile of up to 48 labels** (`Raptor.profileWidth`), not one earliest arrival. One forward pass covers a whole window of departures.
- **Dominance only among labels with the same trip chain** (same sequence of `(trip, service date)`, same alighting position, same preferred-mode flag). Different vehicle chains never dominate each other; only quotas bound them.
- **Arrive-by is a forward search** over `[T − horizon, T]`, not a reverse RAPTOR.

### 5.2 Label (`Raptor.Label`, compact form `Raptor.ScanKey`)
Arrival time; first boarding deadline; door departure (= first boarding − access walk); linked predecessor + appended leg; last transit leg; minimum and total transfer slack; access, pathway and transfer-walk seconds/distance; `transferWalkSeconds` since last ride; `containsPreferredMode`; `walkingStopsVisited`; `tripKey` (inline storage for 4 trips + overflow).

### 5.3 Round (`kit:Routing/RaptorSearch.swift`)
1. **Window**: depart-after `[anchor, anchor + h]`; arrive-by `[anchor − h, anchor]`. With live data the scheduled lower bound is `start − lookback` (20 min initial, 10 min later pages) to admit late vehicles. Relevant service days include after-midnight times.
2. **Initial labels**: one per access edge at `start + walk`.
3. **Destination pruning** (`Raptor.DestinationReachability`, cached per session): stops that can reach egress with k more rides (one reversed walk batch + continuations; no walk chains). Patterns whose last useful alight position ≤ earliest marked boarding position are skipped. Final round may only alight at egress stops or one hop from them.
4. **Mark patterns** touched by labelled stops; record earliest position.
5. **Prepare trip instances** (`Raptor.activeTripInstances`, cache `PreparationCache` 4,096 entries keyed by trip+date, valid while overlay unchanged): mode mask, active service, window overlap, cancelled/unreachable → excluded, live effective times, non-chronological → excluded, conservative deadline (INV-5), boarding/alighting permissions, at least one pickup ≥ start.
6. **Parallel scan** if ≥32 patterns: up to 10 workers (`maximumPatternWorkers`), `workers × 12` chunks, costly chunks first, merge in chunk order (INV-7).
7. **Inner loop** (`scanPatternsCompact`), per trip instance:
   - eligible alighting positions computed once (drop-off, live permission, scheduled arrival exists, can still reach destination, final-round restriction, wheelchair/bike);
   - for each boarding position from the earliest marked one: pickup allowed, live boarding allowed; deadline = conservative departure; eligible source labels = those arriving ≤ deadline (64-bit mask);
   - per source: not already on this instance; `cachedTransferDecision`; `additional = max(buffer, required − transferWalk)` (0 for first ride); feasible if `deadline ≥ arrival + additional`; slack updated;
   - for each later eligible alight: build `ScanKey`, `consider()` → `isDominated` → `cannotEnter` → `insert`.
8. **Merge** chunk profiles; materialise `Label`s for survivors only.
9. **Continuations** (`relaxContinuations`): explicit type 4 or unique block successor; consumes no round; no transfer buffer.
10. **Pathways** (`relaxPathways`): BFS; none in current feed.
11. **Walking transfers** (`relaxWalkingTransfers`), skipped for wheelchair-required: from post-ride labels to `nearbyTransferStopsByStop`; one routed walk per stop pair applied to every eligible label; accepted if routed, ≤15 min, ≤1.5 km, arriving before the target's latest useful boarding (`walkingBoardingDeadlines`, recomputed in every round that allows a further ride) unless the target is an egress stop. One walking batch per round.
12. **Collect** labels at egress stops with ≥1 ride as `Candidate`s.

### 5.4 Transfer decision (`kit:Routing/RaptorPreparation.swift`)
- First ride: no minimum.
- `selectedTransferRule`: candidate rules from 4 group keys, filtered by endpoint/trip/route scope; most specific wins (trip→trip 60, trip+route 50, trip 40, route→route 30, one route 20, stop 10), then concrete stop over station, then stricter type (3 > 5 > others), then later row.
- Type 3 → forbidden. Otherwise required = `max(rider minimum, min_transfer_time)`; no rule → rider minimum (120 s, 180 s with "avoid tight transfers").
- **Bus exception** (`permitsTightSameStopBusTransfer`): bus→bus at the same plain stop under an unscoped same-stop type-2 rule, with `allowTightSameStopBusTransfers` (app: `true`) → required = `max(120, rider minimum)`; the feed value is kept as `recommendedTotalTransferSeconds`.
- Cached per chunk in `[TransferDecisionKey: CachedTransferDecision]` (key: incoming trip, incoming alight stop, boarding stop, outgoing trip).

### 5.5 Profile quotas and dominance (`kit:Routing/RaptorCompactProfile.swift`)
- Dominance (same trip chain, same alight position, same preferred flag): slack ≥, door departure ≥, arrival ≤, walking ≤, one strict.
- Quota = 48 / 5 = 9 protected per list: first 9 and last 9 by departure order, 9 earliest arrivals, 9 least walking, 9 earliest preferred-mode arrivals (only with a preferred mode). On a 49th label, evict the latest-arriving unprotected label. `cannotEnter` rejects a candidate that would be evicted immediately unless it could remove a dominated peer.

### 5.6 Candidates → journeys (`JourneyPlanningSession.buildJourneys`)
1. `RaptorWalkingShortcut.normalize`: replace ride + walk by riding on when the same instance serves the walked-to stop no later.
2. `JourneyStructuralValidator.assess` (INV-2).
3. `buildJourney`: door times, anchor check, accessibility evidence, legs, signature `g<gen>:<first>><last>:<trip>@<date>:<board>-<alight>|…`, `JourneyPublicationValidator`.
4. Deduplicate by signature (better rank wins).
5. Group by `equivalentTransferKey` (same vehicles and endpoints, different change point) with equal times and walking within 2 min / 200 m → keep the safer transfer (`min(minSlack, 600) − walking`).
6. `strictEnvelope` → `JourneyQualityPolicy.envelopeIDs` (§7.2).
7. Add intermediate stops for survivors.

---

## 6. Live data

### 6.1 Provider
`HafasRealtimeRoutingProvider` exists only when the relay URL is configured (`Config/AppConfig.xcconfig` `API_PROXY_URL`). Settings: 32 concurrent boards (shared scheduler), 60 s board cache (`DepartureBoardCache`, static/shared), 4 s request timeout. Request from app: 8,000 ms budget, 32 concurrent.

### 6.2 Discovery targets (`JourneyPlanningSession+Realtime.swift`)
Planning bounded to `min(250 ms, budget / 10)`. Start from ≤8 access stops (fewest rides to destination, then shortest walk) + stops of selected itineraries. Up to 4 waves; each advances an optimistic reachability envelope (`RealtimeReachability.advance`: a departure up to 20 min before arrival counts, modelling a late vehicle). Next frontier ≤8 stops (rides to destination, distance to destination, arrival). Total ≤24 stops. Per stop ≤8 departure seeds → windows `[dep − 60 s, +90 min]`, line filter if all lines named. Short trips (≤2 h) covered by their passlist are not re-fetched downstream.

### 6.3 Itinerary completion (`+ItineraryRealtime.swift`)
For each ride of the current top picks not already reported within 60 s, one attempt per (instance, boarding sequence): board window `[min(sched, eff) − 60 s, max(eff + 60 s, sched + 2 h + 60 s)]`, filtered to the line.

### 6.4 Acquisition (`+Acquisition.swift`)
Stops ordered by cached coverage. One work unit per stop holds a permit; windows rounded to 30 min, merged, split at 1,439 min (ATP limit), ≤8 slices. `rtMode=SERVER_DEFAULT`, `passlist=1`, unlimited journeys. Batch deadline with 500 ms (or ¼ remaining) reserved for matching; partial coverage kept on timeout. GTFS schedules for matching are prepared concurrently from SQLite (≤4,000 departures per stop).

### 6.5 Matching (`+Matching.swift`, `+Events.swift`)
Row needs a live signal. Planned time ±90 s window. GTFS candidates at the stop within ±90 s; score: `lineID == route_id` 6 or name match 4 (else excluded), +2 direction = headsign, +1 per aligned passlist stop up to +4. Cancelled rows need direction match or ≥2 aligned stops. Tie on score and time → rejected as ambiguous. Patch per stop: reported times; delay propagated ≤30 min as estimated; platform priority; boarding/alighting permissions; minute-precision fix; non-chronological → dropped. Repeated autumn DST hour → rejected (TODO in code).

### 6.6 Resolution (`RealtimeTimeline.resolved`)
Observation older than 120 s or >60 s in the future, |delay| > 2 h, propagation > 2 h, or non-chronological → instance becomes `unreachable` (excluded). Otherwise last explicit delay propagated forward as estimated. Merge rule: within 120 s, reported > estimated > scheduled; else newer observation wins.

---

## 7. Ranking and publication

### 7.1 Score (`JourneyQualityPolicy.score`)
`(arrival − anchor) + 300 s × transfers + 1 × walking seconds` (arrive-by: `anchor − door departure`). `ranksBefore`: not cancelled → (arrive-by: later departure) → preferred mode → accessibility → score → departure → arrival → ID.

### 7.2 Filters
- Pareto `dominates`: same accessibility and preferred flag; departure ≥, arrival ≤, transfers ≤, walking ≤, one strict; a dominator with a tight transfer cannot remove one without.
- Envelope: removed if another journey leaves no earlier, arrives no later, has ≤ transfers and is a redundant access feeder, or walks ≤ +300 s and dominates or removes a redundant intermediate change.
- `clearlyInferiorInInitialProfile`: another leaves 0–20 min earlier, arrives ≥10 min earlier, ≥10 min shorter, ≤ transfers/walking.
- `materiallyInferior`: same-vehicle near-duplicates collapse; or another with ≤ transfers/walking (strictly fewer transfers or ≥2 min less walking), catchable together, arriving ≤2 min later.

### 7.3 Selection (`primarySuggestions`, count 6)
Best by rank; reserve a fallback (different first vehicle, score within 15 min, door departure after best's first vehicle leaves); fill with ≤2 per first vehicle; sort chronologically. Recommendation: best rank, or the direct walk if it arrives earlier (fastest preference). Publication re-validates all accumulated journeys (`JourneyResultSession.snapshot`), applies filters across pages, keeps the previous recommendation unless the new one scores ≥60 s better.

### 7.4 App presentation
- `RouteOptionVisibility.visibleOptions`: hides any option another selectable option beats on departure and arrival time alone (see CAND-15).
- `JourneySelectionPolicy`: manual choice → recommendation → first selectable.
- Walking refinement after render: re-route provider walks (full Valhalla search) through `LocalFirstRoadRouteProvider`, retime (access walk anchored backwards from boarding), submit to `JourneyResultSession.submitWalkingRefinement`, which corrects the engine walking cache, revalidates, and runs one replacement search if a journey became invalid.

---

## 8. Constants

| ID | Constant | Value | Where |
|---|---|---|---|
| C-1 | Max transfers / rounds | 3 / 4 | `RoutingPreferences(preferredMode:avoidTightTransfers:)` |
| C-2 | Rider minimum transfer | 120 s (180 s avoid-tight) | same |
| C-3 | Tight threshold | 180 s | `JourneyItineraryValidator.tightTransferThresholdSeconds` |
| C-4 | Profile width / quota | 48 / 9 | `Raptor.profileWidth` |
| C-5 | Initial / max window | 2 h / 24 h, doubling | `JourneyBatchPolicy.initialHorizon`, `Raptor.fullProfileHorizon` |
| C-6 | Suggestions per page | 6 (earlier pages 3) | `JourneyBatchPolicy` |
| C-7 | Long-distance pre-pass | ≥40 km straight line | `shouldPrepareLongDistanceHorizon` |
| C-8 | Endpoint candidates | ≤3 km, 40 (24 + 16 if <8 survive) | `endpointCandidateLimit`, `initialEndpointCandidateLimit` |
| C-9 | Access/egress walk | ≤30 min, ≤3 km | `endpointEdges` |
| C-10 | Direct walk | ≤45 min, ≤3 km (straight line ≤3,050 m) | `directWalk` |
| C-11 | Transfer walk | ≤15 min, ≤1.5 km; ≤8 within 450 m / ≤12 within 900 m | `relaxWalkingTransfers`, `nearbyTransferStops` |
| C-12 | Walking calibration | ×1.25 | `WalkingDurationCalibration` |
| C-13 | Live budget / concurrency | 8,000 ms / 32 | `MobiliteitRouteService` |
| C-14 | Completion waves | ≤2 | `generate` |
| C-15 | Board cache / request timeout | 60 s / 4 s | `JourneyPlanner.router(for:)` |
| C-16 | Scheduled lookback | 20 min (10 later) | `JourneyPlanningPage.realtimePolicy` |
| C-17 | Board forward horizon | 90 min | `RealtimeConfiguration.minimumForwardHorizonSeconds` |
| C-18 | Max delay / propagation | 2 h / 2 h (30 min when building a patch) | `RealtimeTimeline` |
| C-19 | Freshness | reuse <60 s, invalid >120 s | `retainingFreshObservations`, `maximumObservationAge` |
| C-20 | Score weights | 300 s per transfer, ×1 walking | `JourneyQualityPolicy` |
| C-21 | Recommendation hysteresis | 60 s | `JourneySuggestionPolicy` |
| C-22 | Workers | ≤10, from 32 marked patterns | `Raptor.maximumPatternWorkers` |
| C-23 | UI first-result deadline | 15 s | `RoutePlannerModel.routeCalculationTimeout` |

---

## 9. Baseline live benchmark

Raw evidence: `docs:benchmarks/live-baseline-2026-10-15/` (`samples.json` has
every span, pass, round, counter and journey; `transport-summary.json` has every
ATP request without response bodies).

### 9.1 Setup

| Item | Value |
|---|---|
| When | 2026-10-15, planning time 17:51 CEST (evening peak) |
| Route | Gromscheed (coordinate 49.6541071, 6.2296443) → Kirchberg, Konrad Adenauer (stop `000200417019`), leave now |
| Scenario | `live-now` in `app:App/Benchmarks/SimulatorRouteBenchmark.swift` |
| Command | `python3 Scripts/benchmark_routes.py --app <Release .app> --output <dir> --scenarios live-now --warm 1 --cold 1 --maximum-limit-ms 0` |
| Build | Release, `ENABLE_CODE_COVERAGE=NO`; app `9110b4a` plus uncommitted UI-only edits (`MainSheet.swift`, strings); engine `c4f4b70` |
| Machine | MacBook Air M4 (10 cores, 16 GB), Xcode 27.0, iPhone 17 simulator, iOS 27.0 |
| Data | GTFS generation 6; walking graph 20260921; stored transfer walks rebuilt by the harness first (11,188 pairs, 477 without a route, 6.2 MB, 8.0 s) |
| Live | Real ATP through the relay; the harness uses `forceRefresh` for every sample; live bike availability |
| Samples | **priming** = first search in a fresh process after launch; **warm** = second search in that process; **cold** = first search in another fresh process. n = 1 each. |
| Clock | From the model's calculation start to two display callbacks after the result sheet commits (`docs:ROUTE_CALCULATION_PERFORMANCE.md` §Acceptance boundary). Walking refinement after render is not included. |

### 9.2 Totals

| Sample | Total (ms) | ≤ 5,000 ms gate | ATP requests | Decoded board bytes | Boards covered | Live predictions | Peak RSS |
|---|---:|---|---:|---:|---:|---:|---:|
| priming | **10,058** | fail | 27 | 17.9 MB | 26 | 4,089 | 768 MB |
| warm | **7,053** | fail | 19 | 10.7 MB | 18 | 2,739 | 768 MB |
| cold | **7,655** | fail | 27 | 17.9 MB | 26 | 4,059 | 816 MB |

All three searches returned the same 6 engine journeys and the same recommendation.

### 9.3 Critical path

Segments are sequential; parallel work is in the last column.

| Segment | priming | warm | cold | Runs in parallel |
|---|---:|---:|---:|---|
| Setup (snapshot ∥ walking graph, then endpoints) | 1,228 | 104 | 1,118 | `snapshotPreparation` 916 / 11 / 866; `graphPreparation` 640 / 23 / 513; `endpoints` 282 / 29 / 235; bike branch |
| Live acquisition (discovery + speculative completion) | **4,070** | **3,259** | **2,563** | warm-up scan 1,679 / 2,140 / 1,260 + preliminary build 363 / 519 / 343 |
| RAPTOR pass 1 (2 h window) | 1,700 | 1,288 | 1,148 | – |
| Candidate building | 364 | 354 | 313 | – |
| Completion wave 1 (live) | 352 | 440 | 365 | – |
| RAPTOR pass 2 (wave 1 changed routing inputs) | 1,267 | 1,062 | 1,351 | – |
| Candidate building | 361 | 328 | 354 | – |
| Wave 2 (≈11 ms, nothing new) + assembly → publication | 67 | 48 | 76 | – |
| First render | 649 | 170 | 366 | walking refinement starts at publication |
| **Total** | **10,058** | **7,053** | **7,655** | |

Rows add up to each total within rounding. The second completion wave took ≈11 ms and found nothing new,
so only two authoritative passes ran. The 2 h window was enough; no horizon doubling.

Approximate share of the warm total: live acquisition including matching 52 %,
RAPTOR scans 33 %, candidate building 10 %, render and assembly 3 %, setup 1 %.

### 9.4 RAPTOR pass anatomy (cold sample)

| Pass | Duration | Round | Alighting checks | Retained (pre-merge) | Scan ms | Merge ms | Prep ms |
|---|---:|---|---:|---:|---:|---:|---:|
| 1 | 1,148 | 1 | 4,279 | 2,731 | 2 | 3 | 1 |
| | | 2 | 822,551 | 217,809 | 65 | 131 | 12 |
| | | 3 | 5,398,404 | 634,807 | 234 | 210 | 3 |
| | | 4 | 668,895 | 70,896 | 37 | 10 | 0 |
| 2 | 1,351 | 1 | 4,279 | 2,731 | 1 | 4 | 0 |
| | | 2 | 822,551 | 217,809 | 58 | 111 | 11 |
| | | 3 | 5,398,404 | 634,807 | 284 | 221 | 3 |
| | | 4 | 668,895 | 70,889 | 64 | 24 | 0 |

Per pass in the cold sample, scan + merge + prep is ≈708 ms (pass 1) and
≈781 ms (pass 2). Walking transfers (`walkingTransfers`, 519 ms over both
passes) are mostly cache hits: 27,827 walking requests, 22,327 hits. The rest
of each pass, ≈180–390 ms across the three samples, is not attributed by any
round metric. It includes `BoardingIndex`
construction, `walkingBoardingDeadlines`, candidate collection and
continuation/pathway relaxation outside `merge_ms`.

**Merge costs as much as the parallel scan**, about 350 ms of ≈700 ms per pass.
It is serial: every retained chunk label is re-inserted in chunk order. Round 3 does 5.4 M alighting checks
per pass. Both passes produce 3,600 candidates, which collapse to 26 retained
alternatives (≈855–880 suppressed as duplicates, 11–12 invalid).

### 9.5 Live transport (73 requests over the three samples)

| Metric | Median | p90 | Max | Sum |
|---|---:|---:|---:|---:|
| Request total (ms) | 1,324 | 1,984 | 2,640 | 90,812 |
| Server wait, relay + ATP (ms) | 718 | 1,346 | 1,898 | 57,819 |
| Transfer (ms) | 69 | 163 | 356 | 6,387 |
| Encoded (compressed) bytes | 20,963 | 54,112 | 70,193 | 1.8 MB |
| Decoded JSON bytes | 474,294 | 1,488,334 | 1,950,550 | 46.4 MB |

- Every request covered **150 minutes**: per-stop target windows of up to 90 minutes each, merged and rounded out to 30-minute boundaries. All used `passlist=1`, `maxJourneys=-1` and a line filter. Compression ratio ≈25.6×.
- Busiest boards: Kirchberg stops `000200417039` (13 lines, 1.95 MB decoded), `000200417033` (1.70 MB) and `000200417019` (1.53 MB).
- No URL was fetched twice within one search. Repeats across samples come from the harness's forced refresh.
- Protocols h2/h3 with connection reuse. Latency is dominated by server wait, not transfer.
- Matching rejections: 12–24 `outsideInterval`, 1 `noCandidate`; no ambiguity rejections.

### 9.6 Results

| Shown | Door departure → arrival | Lines | Notes |
|---|---|---|---|
| yes, recommended | 17:55:45 → 18:24:00 | 850 → 6 | 850 scheduled 17:51:56, running 13 min late (`delayedPastBoardings`). Only catchable because of live data and the 20-minute lookback. 2-minute "tight" change. |
| **hidden by app** | 17:58:45 → 18:31:00 | 223 → 16 | Kept by the engine, hidden by `RouteOptionVisibility` because 29 → 16 leaves later and arrives at the same time. The engine keeps it, so it differs on walking or accessibility evidence (see CAND-15). |
| yes | 18:00:40 → 18:31:00 | 29 → 16 | |
| yes | 18:08:45 → 18:40:00 | 321 → 6 | |
| yes | 18:14:31 → 18:40:00 | 322 → 6 | 2:55 change = tight. 322 schedule-only (no live data for it yet). |
| yes | 18:14:31 → 18:50:13 | 322 → 21 + walk | Same first bus, 10 min later. Kept because a journey with a tight transfer cannot dominate one without. |

Bike share: one vel'OH! supplemental option.

### 9.7 How to read these numbers

- n = 1 per sample type, on live data at peak time. Identical runs vary 10–20 % (EXP-6). Live inputs differ between samples.
- Not comparable to the 14 October live check (`docs:benchmarks/transfer-walks-2026-10-14/README.md`: cold 4,467 / priming 5,712 / warm 3,657 ms on the same route). That run used feed generation 5, an older engine revision, different live conditions and may have needed a single pass.
- A simulator on a laptop is not a phone. Decoding 10–18 MB of JSON and 770–816 MB peak RSS will matter more on an iPhone.
- The harness forces live refresh. A normal second search within 60 s would hit the board cache.

### 9.8 What the baseline suggests

1. **Live acquisition is the largest single block** (2.6–4.1 s). Board latency is mostly server wait, and payloads are large. Candidates: CAND-7, CAND-12.
2. **A completion wave triggers a second full scan + build in every sample** (≈1.8–2.1 s including the wave, 20–27 % of the total). Making pass 1 final more often, or making a rescan cheaper, targets that share. Candidates: CAND-13, CAND-11, CAND-1, CAND-2.
3. **Merge ≈ scan** inside each pass, and merge is serial. Candidate: CAND-11.
4. **Candidate building runs three times** (preliminary + after each pass) at ≈310–520 ms each for 3,600 candidates. Candidate: CAND-3.
5. **Cold start adds ≈0.9–1.2 s** (snapshot 866–916 ms in parallel with the walking graph 513–640 ms, then endpoints). Candidates: CAND-5, CAND-6.
6. **First render** ranges from 170 to 649 ms and overlaps walking refinement. Candidate: CAND-14.

---

## 10. Past experiments and known facts

| ID | What | Result |
|---|---|---|
| EXP-1 | Stored transfer walks (precomputed ≈11,188 pairs) | Identical results; fresh-process depart −68 %, exact −83 %; arrive-by −35 % fresh, no warm gain. `docs:benchmarks/transfer-walks-2026-10-14/` |
| EXP-2 | Per-instance setup (lazy alights, cached static alight eligibility) | No measurable gain: ~144k trip instances vs ~347M alighting checks. |
| EXP-3 | Classic target pruning (drop a label if a known journey leaves no earlier and arrives no later) | −54 % total time but changed 9 of 33 routable result sets and surfaced journeys with 4-hour waits (freed quota slots let `totalSlack` keep junk). Rejected under INV-4. |
| EXP-4 | Profile of busy CPU (release, 12 stop pairs) | `Raptor.consider` (dominance/quota) ≈40 %; dictionary hashing in `cachedTransferDecision` / `selectedTransferRule` ≈15 %; `CompactProfile.insert` notable. |
| EXP-5 | Conversion memoisation in live matching | Matching 2,926 ms → 173 ms on the same recorded boards. `docs:ROUTE_CALCULATION_PERFORMANCE.md` |
| EXP-6 | Noise | Identical runs vary 10–20 % (one run +60 %). Alternate A/B runs and compare result hashes. Debug is ≈20× slower than Release. |

---

## 11. Candidate improvements

Each candidate is a hypothesis, not a decided change. "Exact" means results
must stay identical (INV-1). Effort and gain are rough guesses; measure first.

### 11.1 Summary

| ID | Kind | Exact? | Area | Short description |
|---|---|---|---|---|
| CAND-1 | speed | yes | kernel | Precomputed transfer-decision fast path instead of per-chunk dictionary + rule search |
| CAND-2 | speed | yes | kernel | Cheaper profile bookkeeping in `consider` / `CompactProfile.insert` |
| CAND-3 | speed | yes | candidates | Build full `Journey`s only for signature representatives |
| CAND-4 | speed | yes | kernel | Stop recomputing `walkingBoardingDeadlines` from the whole feed every round |
| CAND-5 | speed | yes | cold start | Persist the routing snapshot instead of rebuilding it from SQLite per process |
| CAND-6 | speed | yes | endpoints | Start access/egress walking work before the user taps "Go" |
| CAND-7 | speed | no (live) | live data | Cut live-acquisition wall time (relay cache, prefetch, fewer boards) |
| CAND-8 | speed | no | arrive-by | Bring arrive-by under the 5 s gate |
| CAND-9 | speed | research | horizon | Avoid rescanning the already-searched window when doubling the horizon |
| CAND-10 | speed | experiment | live data | Re-evaluate the warm-up scan now that transfer walks are stored |
| CAND-11 | speed | yes | kernel | Merge chunk profiles per stop in parallel with precomputed IDs |
| CAND-12 | speed, memory | yes (relay trim) / no (windows) | live data | Shrink departure-board payloads (474 KB median decoded) |
| CAND-13 | speed | no (live) | live data | Make the first authoritative pass final more often (avoid pass 2) |
| CAND-14 | speed (UX) | yes | app | Start walking refinement after the first render |
| CAND-15 | quality | n/a | app | App visibility hides fewer-transfer / less-walking options |
| CAND-16 | quality | n/a | live data | Stale frozen evidence may invalidate journeys on later pages |
| CAND-17 | hygiene | yes | API | Remove preference fields that do nothing |
| CAND-18 | determinism | no (cm) | walking | Funicular ride distance depends on process history |
| CAND-19 | hygiene | yes | walking | Valhalla config files accumulate in Application Support |
| CAND-20 | robustness | n/a | live data | Repeated autumn DST hour discards live rows |

### 11.2 Details

#### CAND-1 Transfer-decision fast path
- **Evidence**: EXP-4 (≈15 % of busy CPU in `cachedTransferDecision` / `selectedTransferRule`). The cache `decisions` is a local in `scanPatternsCompact`, so it restarts for every chunk, round and scan; its key includes both trip indices, so the key space is large. Every miss runs `selectedTransferRule`, which builds four `RuleGroupKey`s, `flatMap`s, sorts and filters arrays. Feed: all 2,904 rules are same-stop and only 213 are route/trip scoped.
- **Change**: at snapshot build, precompute per `(from group, to group)` the winning *unscoped* rule (or "none") and a flag "pair has scoped rules". In the scan: if the pair has no scoped rules, derive the decision from the precomputed rule plus the two route types (bus exception) without hashing; otherwise fall back to the existing path. Optionally share a decision cache across chunks of a round.
- **Where**: `kit:Routing/RaptorPreparation.swift` (`transferDecision`, `selectedTransferRule`, `permitsTightSameStopBusTransfer`), `kit:Routing/RaptorCompactScan.swift`, `kit:Routing/RaptorReferenceScan.swift`, `SnapshotBuilder.load`.
- **Risk**: precedence must match exactly (score, endpoint score, restriction, order). `buildJourney` and `RaptorWalkingShortcut` call `transferDecision` too; keep one implementation.
- **Verify**: `ROUTING_VERIFY_KERNEL=1`; add a test that compares fast path and full path for every rule pair in a fixture feed; equivalence replay.

#### CAND-2 Profile bookkeeping
- **Evidence**: EXP-4 (`Raptor.consider` ≈40 %). `CompactProfile.byIncomingTrip` is a `[Int: UInt64]` dictionary hashed on every `isDominated`, `cannotEnter`, `insert` and `remove`; `insert` re-runs `quotas()` (five passes over up to 48 slots) whenever the profile is full; three sorted index arrays use `Array.insert`/`remove(at:)`.
- **Change**: replace `byIncomingTrip` with a small inline array of `(trip, mask)` (≤48 entries, linear scan); maintain quota membership incrementally; keep slot arrays fixed-size.
- **Where**: `kit:Routing/RaptorCompactProfile.swift`, `kit:Routing/RaptorCompactScan.swift` (`consider`, `incomingPeers` handling).
- **Risk**: eviction order and tie-breaks must be bit-identical (INV-7, INV-8).
- **Verify**: `ROUTING_VERIFY_KERNEL=1 swift test --no-parallel`; journey hashes on the installed feed.

#### CAND-3 Build journeys only for representatives
- **Evidence**: `candidateBuilding` ≈310–520 ms per call, three calls per search (§9.3). 3,600 candidates become 26 retained, with ≈855–880 suppressed as duplicates. `buildJourneys` fully builds every candidate (normalisation, validation, legs, string signature, publication validation) and only then keeps one per signature; it runs after every authoritative scan and again on overlay-only changes.
- **Change**: compute the signature and ranking fields from the `Candidate` first, order candidates per signature by rank, and fully build in that order until one passes validation (an invalid one must never suppress a valid one).
- **Where**: `JourneyPlanningSession.buildJourneys`, `buildJourney` in `kit:Routing/TransitRouter.swift`.
- **Risk**: `prefers` uses `JourneyQualityPolicy.ranksBefore` on built journeys (walking duration after normalisation, accessibility, preferred mode). Derive the same values, or build lazily.
- **Verify**: equivalence replay; count `duplicatesSuppressed` before/after.

#### CAND-4 Cache walking boarding deadlines
- **Evidence**: §9.4. ≈180–390 ms per pass is not attributed by any round metric; this function is one of the unmeasured steps. Add a span for it first. `Raptor.walkingBoardingDeadlines` iterates every pattern × trip × relevant day × stop time on every round with a further ride (3 rounds per scan, up to 4 scans per window, more with horizon doubling), including a dictionary lookup per (trip, day).
- **Change**: compute the scheduled part once per session per `lastAlightPositions` level, then overlay only patched trip instances; or cache by `(remainingRides, patch revision)`.
- **Where**: `kit:Routing/RaptorBoardingDeadlines.swift`, call site in `kit:Routing/RaptorSearch.swift`.
- **Risk**: low; deadlines are an upper bound used only for pruning. Must stay ≥ the true value.
- **Verify**: assert equality of the deadline arrays in `ROUTING_VERIFY_KERNEL` mode; time the `raptor` stage.

#### CAND-5 Persist the routing snapshot
- **Evidence**: `snapshotPreparation` 866 ms (cold) and 916 ms (priming), on the critical path in parallel with `graphPreparation` 513–640 ms (§9.3). `SnapshotBuilder.load` re-reads 641k stop times, rebuilds patterns, nearby stops and continuation index in every new process. The benchmark harness deliberately charges this to the first request.
- **Change**: write a versioned binary snapshot next to the GTFS database at install time (like `docs:TRANSFER_WALKS.md`: header with feed generation and algorithm version, checksum, memory-mapped load), falling back to SQLite.
- **Where**: `kit:Routing/TransitRouter.swift` (`SnapshotBuilder`), `JourneyPlanner.router(for:)`.
- **Risk**: stale caches; key on database fingerprint + snapshot algorithm revision.
- **Verify**: snapshot equality test (all arrays equal); cold `snapshotPreparation` before/after.

#### CAND-6 Start endpoint work earlier
- **Evidence**: `endpoints` 235–282 ms cold/priming, 29 ms warm (§9.3). Each new session measures up to 24 (+16) access and egress walks with Valhalla. Origin→stop walks are not in the stored transfer table (that only holds stop→stop pairs).
- **Change**: when a destination or origin is chosen (before "Go"), warm `WalkingRouteCache` for the endpoint candidates via a new engine API (e.g. `TransitRouter.prepareEndpoint(_:)`), reusing `endpointEdges`' exact candidate selection.
- **Where**: `JourneyPlanningSession.endpointEdges`, `RoutePlannerModel` (destination selection), `MobiliteitRouteService`.
- **Risk**: wasted work if the user changes their mind; GPS origin moves. Exact: same requests, only earlier.
- **Verify**: `endpoints` stage drops; results identical on replay.

#### CAND-7 Live-acquisition wall time
- **Evidence**: §9.3/§9.5. Live acquisition takes 2.6–4.1 s (52 % of the warm total), plus 0.35–0.44 s for the completion wave. Per request, the server wait (relay + ATP) has a median of 718 ms and p90 1.35 s; transfer only 69 ms. 19–27 requests per search.
- **Options**: (a) shared short-TTL caching of ATP boards in the relay (`verkeier-relay` Cloudflare Worker); (b) prefetch boards for the origin's access stops when the planner opens (ATP quota permitting); (c) fewer discovery stops or seeds when the first scan already proves feasibility; Connection reuse is already in place (h2/h3, reused connections in §9.5).
- **Where**: `kit:Routing/HafasRealtimeRoutingProvider+Acquisition.swift`, `JourneyPlanningSession+Realtime*.swift`, `kit:DepartureBoardCache.swift`, relay repo.
- **Risk**: INV-5 and INV-6; ATP quota and terms (`docs:DATA_SOURCES.md`). Not exact by nature; compare live coverage and journey quality.
- **Verify**: repeated live benchmarks, alternating A/B (replay cannot be used when requests change, §12.4); count `networkRequests`, `boardCacheHits`, `incompleteBoards`, live coverage of shown journeys.

#### CAND-8 Arrive-by under the gate
- **Evidence**: `docs:benchmarks/transfer-walks-2026-10-14/README.md`: arrive 6,126 ms fresh, 6,292 ms warm (gate 5,000 ms); a live arrive-by search costs ≈68 ATP requests. Arrive-by runs a forward profile over `[T − h, T]` and doubles `h` until `ArrivalSearchStoppingPolicy` is satisfied.
- **Options**: reverse (latest-departure) RAPTOR for arrive-by; a tighter but still safe stopping proof; reuse of the previous window's labels.
- **Where**: `kit:Routing/RaptorSearch.swift`, `ArrivalSearchStoppingPolicy.swift`, `initialSuggestions`.
- **Risk**: high; a reverse search needs its own dominance/transfer semantics and the full INV list. Results will differ; define acceptance by quality invariants and comparison with the current output.

#### CAND-9 Incremental horizon expansion
- **Evidence**: the baseline route needed only the 2 h window, but sparse routes and arrive-by double it (`passes[].horizon_s` in `samples.json`). Doubling 2→4→8 h reruns `generate` from scratch over the already-searched window.
- **Change**: research only. Quotas make the 4 h profile not a superset of the 2 h profile, so naive reuse is not exact.

#### CAND-10 Warm-up scan
- **Evidence**: `walkingPreparation` 1.3–2.1 s plus a preliminary build of 0.34–0.52 s, all inside the live-acquisition wait (§9.3). It competes for CPU with decoding and matching. The warm-up was introduced to prime pedestrian paths while boards download; stored transfer walks (EXP-1) now provide those instantly. It still selects speculative completion targets.
- **Experiment**: disable it (`shouldPrepareWalking = false`) on recorded transport and compare total time, live coverage and journeys.
- **Risk**: changes which boards are fetched before the first authoritative scan, so live results can differ.

#### CAND-11 Parallel per-stop merge
- **Evidence**: §9.4, merge ≈350 ms per pass, about equal to the parallel scan. `PatternScanMerge.append` re-inserts every retained chunk label serially (chunk order → sorted stops → slots), running `isDominated`, `cannotEnter` and `insert` for each.
- **Change**: profiles of different stops are independent. Precompute each label's ID from prefix sums: IDs are assigned to every slot before the dominance checks, so they depend only on counts. Then merge each stop's chunk sequence in parallel, preserving chunk order per stop. `materialize` is also per stop.
- **Where**: `kit:Routing/RaptorPatternMerge.swift`, `RaptorCompactScan.materialize`, `kit:Routing/RaptorSearch.swift` (the merge currently overlaps with the scan as chunks finish in order).
- **Risk**: IDs and per-stop insertion order must be bit-identical (INV-7). Keep the `verifyKernel` reference path.
- **Verify**: `ROUTING_VERIFY_KERNEL=1`; `merge_ms` per round; journey hashes.

#### CAND-12 Smaller departure boards
- **Evidence**: §9.5. 73 requests decoded to 46.4 MB (median 474 KB, max 1.95 MB) from 1.8 MB on the wire. `decode` 312–629 ms of cumulative work; peak RSS 768–816 MB. Every request covered 150 minutes with full passlists. Target windows are up to `minimumForwardHorizonSeconds` = 90 min; `acquireStop` merges a stop's windows and rounds them out to 30-minute boundaries.
- **Options**:
  - (a) **Exact:** the relay (`verkeier-relay` Worker) strips JSON fields the app's decoders never read. List the fields read by the HAFAS models in `kit:MobiliteitAPIClient.swift` / `kit:Models.swift` first.
  - (b) Not exact: narrower windows or less rounding.
  - (c) Exact: incremental or streaming decode.
- **Risk**: (a) none for results if every decoded field is preserved; (b) changes live coverage (INV-5, INV-6). `docs:DATA_SOURCES.md` requires agreeing caching rules with ATP before caching in the relay.
- **Verify**: `responseBytes`, `decode`, peak RSS; replay equality for (a).

#### CAND-13 Avoid the second pass
- **Evidence**: §9.3. In every sample completion wave 1 changed routing inputs (`routingEffectChanged`), costing a second full scan plus build (≈1.4–1.7 s) and the wave's own fetch (≈350–440 ms). The speculative completion during discovery uses the **schedule-only** warm-up's top picks with ≤4 requests. Once live data arrives the top picks change: for example the recommended journey uses a 13-minute-late 850 that the schedule could not select.
- **Change**: record which boards wave 1 fetched and why discovery missed them (instrument `completeItineraryRealtime`). Options: give speculative completion more permits; run a second cheap preliminary selection once the first discovery boards are matched; fetch connecting-line boards for vehicles with large reported delays.
- **Risk**: more ATP requests (quota); not exact by nature. Must keep "every selected vehicle checked" (INV-6).
- **Verify**: count authoritative passes per search (`passes` in `samples.json`) across several live runs and recorded replays; journey quality unchanged.

#### CAND-14 Walking refinement vs first render
- **Evidence**: `firstRender` 170–649 ms. Walking refinement starts at publication (`scheduleWalkingRouteRefinement`) and overlaps the first render (priming: refinement spans of 816 and 473 ms during a 649 ms render). Each refined option calls `applyRouteOptions` on the main actor.
- **Change**: start refinement after `recordRouteResultsRendered`, or batch refined options into one model update.
- **Risk**: refined walk geometry appears a little later. Results are identical.
- **Verify**: `firstRender` over ≥5 samples (high noise).

#### CAND-15 App hides fewer-transfer options
- **Evidence**: `app:Features/Routes/Models/RouteOptionVisibility.swift` `visibleOptions` hides option B if another selectable option departs no earlier and arrives no later (one strict), ignoring transfers and walking. Example: A 08:00→08:40 with 2 changes hides B 08:00→08:45 direct, which the engine deliberately keeps (`JourneyQualityPolicy.dominates` includes transfers and walking). **Seen in the baseline** (§9.6): the engine returned 6 journeys and the app showed 5. It hid 223 → 16 (17:58:45 → 18:31) because 29 → 16 leaves later and arrives at the same time. Both have one change and the later one has no tight transfer, so the engine kept the hidden one for its walking or accessibility evidence.
- **Change**: decide with the product owner; if unintended, apply the engine's dominance (or none) in the app.
- **Verify**: app test with those two fixture options.

#### CAND-16 Stale evidence on later pages
- **Evidence**: `JourneyResultSession.assess` marks a journey invalid when any non-scheduled event on one of its trips was observed more than 120 s ago. A live page refreshes that evidence: the new session seeds from `frozenPatches` trimmed by `retainingFreshObservations`, and `currentPatches()` returns the trimmed copies. A **schedule-only** page does not. `AdjacentJourneySearch` makes windows that end more than 60 s in the past `historical`, which disables live data, so `acquiredPatches` is empty and the old frozen evidence is kept unchanged.
- **Hypothesis**: browsing "Earlier" into the past more than ~2 minutes after the live search makes the engine invalidate the already-listed live journeys. The app's paging baseline (`RoutePagingBaseline`; it subtracts baseline IDs from `invalidatedOptionIDs`) probably hides this from the user, so the effect is engine state diverging from what is shown.
- **Verify first**: an engine test with an injected clock: a live initial search, advance 3 minutes, request a historical earlier page, then inspect `invalidatedIDs`.

#### CAND-17 Dead preference fields
- `RoutingPreferences.frequencyPolicy` is stored and decoded but never read; `TransferAllowance.allowedShortfallSeconds` is always 0; `sameStopTransferShortfallSeconds` is documented as ignored. Remove or implement (`kit:Routing/TransitRouter.swift`, `kit:Routing/RaptorPreparation.swift`).

#### CAND-18 Funicular distance determinism
- `PafendallFunicularConnection` sums `CLLocation.distance` over a fixed track; the value shifts by centimetres after native Valhalla routing runs in the process (`docs:benchmarks/transfer-walks-2026-10-14/README.md`). Use a pure haversine (the engine has `distance(_:_:)`). Changes baseline output by centimetres; record the new value.

#### CAND-19 Valhalla config file accumulation
- Each `ValhallaWalkingRouter` writes `verkeier-valhalla-<datasetVersion>.json` into Application Support. The simulator container had 661 such files (311 `validation-<UUID>` from `ValhallaRoutingDatasetValidator`, the rest from tests in `VerkéierTests/OfflineWalkingRoutingTests.swift` sharing the app container). Delete temporary configs after validation/tests.

#### CAND-20 Repeated autumn DST hour
- `HafasRealtimeRoutingProvider.date(date:time:)` rejects wall-clock times in the repeated hour (TODO in code), so for one hour per year live rows are dropped and routes fall back to schedule. Low priority; needs an ATP offset contract.

---

## 12. How to measure

### 12.1 Prerequisites
- The iPhone 17 simulator must already have the app's timetable and walking graph installed. Launch the app normally once and let onboarding finish.
- Engine changes: edit `../MobilitéitKit`; for app-level measurement, point the app at the local package or push and update the pin.

### 12.2 Build the Release app

```bash
xcodebuild -project Verkeier.xcodeproj -scheme Verkeier -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17' ENABLE_CODE_COVERAGE=NO build
```

```bash
xcodebuild -project Verkeier.xcodeproj -scheme Verkeier -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17' -showBuildSettings | grep -E ' BUILT_PRODUCTS_DIR ='
```

The app is `<BUILT_PRODUCTS_DIR>/Verkeier.app`.

### 12.3 Reproduce this baseline (live; uses ATP quota)

```bash
python3 Scripts/benchmark_routes.py --app <path>/Verkeier.app --output /tmp/live-now --scenarios live-now --warm 1 --cold 1 --maximum-limit-ms 0
```

- About 19–27 ATP requests per search; a live arrive-by search costs ≈68. `--request-budget` (default 200) caps one invocation.
- Output: `samples.json` (per search), `summary.json` (medians), `transport.json` plus `network/` (raw captures; do not commit), `bike-snapshot.json`.
- Other live scenarios: `live-reverse`, `live-arrive`, `live-esch`. Custom routes: `--origin-coordinate`, `--destination-coordinate`, `--destination-stop`.

### 12.4 Exact A/B comparison (no ATP requests)

1. Make one live capture (12.3).
2. Replay it through both builds with the same planning time and bike snapshot. `planningTime` is in `samples.json`.

```bash
python3 Scripts/benchmark_routes.py --app <A>/Verkeier.app --output /tmp/A --scenarios live-now --warm 1 --cold 2 --capture-directory /tmp/live-now/network --bike-fixture /tmp/live-now/bike-snapshot.json --epoch <planningTime> --full-evidence --maximum-limit-ms 0
```

```bash
python3 Scripts/compare_route_benchmarks.py /tmp/A /tmp/B --output /tmp/compare.json
```

Replay needs every board query to match the capture. A change that issues different requests (CAND-7, CAND-12 b, CAND-13) aborts replay. Evaluate those with repeated live runs and quality checks instead.

### 12.5 Engine tests and kernel checks

```bash
cd ../MobilitéitKit && ROUTING_VERIFY_KERNEL=1 swift test --no-parallel
```

- `ROUTING_VERIFY_KERNEL=1` compares compact vs reference kernel, merge, pathways and walking transfers; required for any kernel change (INV-8).
- `ROUTING_REFERENCE_KERNEL=1` runs the slow reference kernel. `ROUTING_VERIFY_PROFILE=1` (Debug) checks profile inserts.
- Run serially: parallel realtime/HTTP mock suites fail randomly.

### 12.6 Engine-only timing and equivalence on the real feed

```bash
cd ../MobilitéitKit && ROUTING_BENCHMARK_DATABASE=<gtfs.sqlite> ROUTING_BENCHMARK_SAMPLES=5 swift test -c release -Xswiftc -enable-testing --filter InstalledTimetableBenchmarkTests
```

```bash
cd ../MobilitéitKit && ROUTING_EQUIVALENCE_DATABASE=<gtfs.sqlite> ROUTING_EQUIVALENCE_OUTPUT=/tmp/equivalence.json swift test -c release -Xswiftc -enable-testing --filter InstalledEquivalenceReplayTests
```

- Find the installed database with `xcrun simctl get_app_container <udid> dev.pedrocordeiro.Verkeier data`, then `Library/Application Support/Mobiliteit/gtfs-generation-*.sqlite`.
- **Date caveat:** these tests use fixed planning dates (2026-09-30, 2026-10-08). The only installed feed (generation 6) starts 2026-10-14. Update the dates in a separate commit, or use a database that covers them.
- Run the equivalence test on the old and new engine revisions and diff the outputs (INV-1).
- Debug is ≈20× slower than Release (EXP-6).

### 12.7 Reporting a change

Report:
- the candidate ID;
- before/after per stage (`stages_ms`), number of passes, and `total_ms` for priming, warm and cold;
- the equality result from 12.4 or 12.6 for "exact" changes;
- for live changes: `networkRequests`, `responseBytes`, `boardsCovered`, realtime coverage of shown journeys, and the journeys list;
- the invariants checked.

Alternate A/B runs; one run per arm is indicative only.

---

## 13. Suggested order

1. **Exact kernel wins, low risk:** CAND-11 (merge), CAND-1 (transfer decisions), CAND-3 (candidate building), CAND-4 (deadlines), CAND-2 (profile bookkeeping). They shorten both passes and the warm-up, are verifiable with `ROUTING_VERIFY_KERNEL` and replay, and need no product decision.
2. **Cold start:** CAND-5, then CAND-6.
3. **Live path, needs the owner and ATP terms:** CAND-12 (a) relay trimming first (exact), then CAND-13 and CAND-7.
4. **Product decisions:** CAND-15, CAND-8.
5. **Hygiene:** CAND-17, CAND-18, CAND-19, CAND-16 test.

## 14. Glossary

| Term | Meaning |
|---|---|
| Trip instance | A GTFS trip on a specific service date: `(trip_id, service date)` |
| Pattern | All trips of one route with the identical ordered stop list |
| Label | One partial journey state at a stop, see §5.2 |
| Profile | The ≤48 labels kept at one stop |
| Trip key / trip chain | Ordered list of trip instances a label has used |
| Round | One RAPTOR iteration = one more vehicle ride |
| Pass | One `Raptor.search` over a window (recorded in `passes`) |
| Wave | A live-completion step between passes |
| Patch | Live evidence for one trip instance (`RealtimeTripPatch`) |
| Board | ATP departure board for one stop and time window |
| Envelope | The quality filter in `JourneyQualityPolicy.envelopeIDs` |
| Priming / warm / cold | First search in a new process / later search in the same process / first search in another new process |
