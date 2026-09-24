# Route quality implementation plan

Prepared 2026-09-23. This is an implementation handoff; no routing changes have been made as part of writing it.

## Objective

Generate journeys that are catchable, respect the requested departure or arrival time, and offer useful choices between travel time, walking, and transfers. Preserve those choices through search, refinement, pagination, deduplication, and selection in the app.

Implement all six findings from the routing review:

1. Preserve worthwhile alternatives with fewer transfers or less walking.
2. Revalidate journeys when pedestrian travel times change.
3. Support useful journeys requiring two or three transfers.
4. Improve endpoint and interchange candidate selection.
5. Implement genuine arrive-by planning.
6. Enforce mode and accessibility preferences during route generation.

Do not expand this into a UI redesign, a replacement routing backend, or an unrelated performance rewrite. Small model and presentation changes needed to expose feasibility, accessibility uncertainty, or search limits are in scope.

## 1. Repository orientation and baseline

### Two repositories must change together

| Repository | Local root | Responsibility |
|---|---|---|
| Verkéier | `/Users/REDACTED/Developer/Verkeier` | App adapter, walking providers, route selection, presentation, integration tests |
| MobiliteitKit | `/Users/REDACTED/Developer/MobilitéitKit` | GTFS snapshot, journey search, preferences, candidate pruning, package tests |

At review time, the package checkout was clean at `106146f423ace2c05cfc6c2cbdb7a3af01735ea6`. The app's [resolved package file][resolved] pins that same revision through a remote package reference in [project.pbxproj][project]. The old `Packages/MobiliteitKit` files are deleted in the current app working tree. **Do not restore or edit that old package copy.**

The app already contains substantial uncommitted work, including routing and walking changes. Record both repositories' status and diff before implementation. Preserve unrelated edits and do not reset either working tree. Re-read source before editing: line numbers in this plan are orientation aids, while symbol names are the durable references.

Read [CLAUDE.md][claude], [codebase rules][rules], and [service documentation][services]. Some documentation is stale: actual source and project settings take precedence. Verified Xcode project, scheme, and test target names are `Verkeier.xcodeproj`, `Verkeier`, and `VerkeierTests`, despite accented names in some command examples.

The actual production dependency chain is wired in [VerkéierApp.swift][app]:

```text
TransitMapViewModel
  → MobiliteitRouteService / MobiliteitRouteEngine
    → TransitRouter / JourneyPlanningSession / Raptor
    → LocalFirstWalkingRoutingProvider
      → LocalFirstWalkingRouter
        → Valhalla, MapKit fallback, straight-line fallback
```

### Validation baseline

The review ran the existing package suite: 29 tests passed. This is a baseline, not evidence that the proposed edge cases are covered. The existing `gromscheedToHamiliusAppRoutePrintsRealGTFSResults` test downloads an archive and returned service dates in 2024; it is not a current-service quality benchmark. New regression tests must use deterministic local fixtures, as required by the app's conventions. The app suite was not run during the review.

## 2. Code map

| Area | Read these symbols | Why |
|---|---|---|
| Public package API | [TransitRouter.swift][router]: `RoutingPreferences`, `RouteQuery`, `Journey`, `JourneyPage` | Add query direction, preference semantics, and quality metadata compatibly |
| Search snapshot | `SnapshotBuilder.load`, `SnapshotTrip`, `SnapshotPath`, `RoutingSnapshot` | Service eligibility, accessibility fields, station relationships |
| Journey construction | `JourneyPlanningSession.generate`, `buildJourney`, `prefers`, `strictEnvelope`, `journeyOrder` | Current time-only pruning and trip-sequence collapsing |
| RAPTOR labels | `Raptor.search`, `scanPatterns`, `insert`, `prefers`, `Label` | Early pruning and eight-label cap can remove future useful journeys |
| Endpoint access | `endpointEdges`, `endpointCandidateLimit` | Closest 24 eligible stops, measured by walking provider afterward |
| Transfers | `nearbyTransferStops`, `relaxPathways`, `relaxWalkingTransfers`, `transferDecision` | Five geographic neighbours, 450 m radius, 96 probes per round, transfer rules |
| Walking cache | [WalkingRouteCache.swift][walk-cache] | Coalescing, cache identity, time-independent cached estimates |
| App adapter | [MobiliteitRouteService.swift][adapter]: `calculateRoute`, `routeCalculationUpdates`, `initialJourneys`, `calculation`, `preferences`, `option` | Hard one-transfer cap, arrive-by approximation, public model mapping |
| Refinement | Same file: `replacingWalkingRoutes`, `replacingLegs`; [RouteService.swift][route-service]: `WalkingRouteRefining` | Geometry updates also change durations without feasibility validation |
| Walking providers | [LocalFirstWalkingRouter.swift][local-walking], [WalkingRouting.swift][walking], [ValhallaWalkingRouter.swift][valhalla] | Matrix estimates, fallback provenance, calibration, pedestrian costing |
| App orchestration | [TransitMapViewModel+RoutePlanning.swift][view-model]: `applyRouteOptions`, `selectBestRouteOption`, `deduplicatingEquivalentRouteOptions`, `filteredRouteOptions`, `compareRouteOptions`, paging/refinement tasks | Post-search filtering and timestamp-only deduplication can undo engine improvements |
| App models | [RouteOption.swift][option], [RoutePlan.swift][plan], [RouteCalculation.swift][calculation], [RoutePlannerModels.swift][planner-models] | Status, timing, transfer metadata, user filters, invalidated IDs |
| GTFS import | [GTFSArchiveInstaller.swift][importer]: table schema, `importTrips`, `importPathways`, stop import | Accessibility and pathway information already exists in storage |

## 3. Behavior contract

Use these defaults unless existing product requirements contradict them. Record any necessary deviation with its reason and tests.

- Depart-after journeys must start at or after the requested instant. Initial access walking is part of the journey.
- Arrive-by journeys must finish at or before the requested instant. Recommend the latest feasible door-to-door departure among the evaluated valid alternatives.
- All legs must have nonnegative duration and a chronologically feasible relationship to adjacent legs. Scheduled and realtime timestamps remain distinguishable.
- Retain meaningful time/walking/transfer tradeoffs. A one-minute advantage alone must not eliminate a substantially easier alternative.
- Search up to three transfers by default; transfer count is a ranking cost, not a blanket one-transfer restriction. Keep explicit caller limits meaningful.
- Return up to five primary transit alternatives when available. A direct walking comparison must not consume a transit slot or remove transit results. Preserve existing supplemental bike alternatives and their ordering contract.
- Keep chronological display and paging separate from the recommendation score. Preserve an explicitly selected journey while it remains valid.
- Mode is a preference for journeys containing that mode, matching the current UI wording; mixed-mode journeys remain eligible. A hard allowed-mode filter is a separate package capability.
- “Prefer accessible options” is a soft preference with transparent uncertainty. A package request for wheelchair access **required** is a hard constraint and must not silently relax.
- Walking fallback estimates are not verified pedestrian or wheelchair routes. Keep provenance through the adapter and into validation.
- Results, IDs, tie-breaking, and page boundaries must be deterministic. A full page is not proof that search was exhaustive.

## 4. Phase A — Establish regression fixtures and quality policy

### Work

1. Extend the fixture builders in [MobiliteitKitTests.swift][kit-tests] and [NearbyStopRoutingTests.swift][nearby-tests]. Factor shared fixture support only where necessary; keep scenarios small and readable.
2. Add failing regression scenarios from the matrix in section 11 before changing the relevant behavior. Do not rewrite existing assertions simply to match new output; explain which previous expectation is intentionally superseded.
3. Extract a small, pure quality policy from the large router file. Suggested responsibilities: dominance, recommendation scoring, preference matching, and deterministic tie-breaking. Keep route search and UI independent of each other.
4. Define named, configurable costs in seconds for walking burden and transfers. Use elapsed door-to-door time and time from the query anchor carefully: a depart-after recommendation must account for waiting before departure, while arrival-deadline ranking must prioritize feasible latest departure. Do not double-count walking already included in elapsed time without naming the additional burden penalty.
5. A reasonable initial calibration hypothesis is an additional five minutes per transfer and an additional one second per walking second. Treat these as proposed product weights, validate against fixtures and representative journeys, and document the final values. They must not replace hard feasibility checks or be used as the sole pruning rule.
6. Preserve `JourneyPreference.fastest`, `.fewerTransfers`, `.lessWalking`, and `.preferDirect` as actually implemented policies. They currently exist in the API but do not influence search.

### Acceptance

- Ranking is deterministic and testable without a database, UI, or network.
- Fixtures explicitly show why a recommendation wins and why the other retained alternatives are still useful.
- No arbitrary UI-order dependency decides which journey survives.

## 5. Phase B — Preserve alternatives through search and presentation

### Package changes

1. Replace the time-only `strictEnvelope` with dominance across door-to-door departure/arrival, transfer count, and walking burden. A journey is dominated only when another is no worse on every relevant dimension and strictly better on at least one. Preserve material preference or accessibility distinctions as needed.
2. Update `Raptor.insert` as well as final pruning. Changing only `strictEnvelope` cannot recover a route already removed at an intermediate stop.
3. Include access duration in comparisons: `firstDeparture` is the first vehicle boarding instant, not door-to-door departure. Labels reaching a stop from different origin walks cannot be compared correctly using boarding time alone.
4. Preserve continuation-relevant state. Incoming trip/route can affect `transferDecision`; a seemingly slower label may be the only label allowed to board a particular connection. Do not merge or dominate labels with incompatible future transfer eligibility merely because they reach the same stop.
5. Replace the unconditional earliest-first `profileWidth = 8` truncation with a bounded policy that preserves useful tradeoffs and temporal coverage. An arrive-by scan must not lose later feasible departures because eight early labels filled the profile. Separate exact dominance from approximate resource limits and expose when a budget truncates exploration.
6. Revisit `JourneyPlanningSession.prefers` and trip-instance representatives. They currently maximize transfer slack before arrival and walking. Cap the benefit of surplus slack in recommendation ranking; waiting longer is not inherently better. If one trip sequence has materially different boarding/walking choices, retain the useful variants until proper dominance is established.
7. If variants survive, extend signatures with the necessary boarding/alighting occurrences and interchange identity. Preserve stable identity across shape updates and realtime refreshes; avoid timing-derived IDs that churn on delays.
8. Remove the direct-walk early return that replaces transit journeys. Keep a direct walk as a separate comparison and bound unreasonable all-the-way walks using a documented policy.

### App changes

1. Replace `DisplayedRouteTimingKey` as the sole equivalence criterion. Two routes showing identical minute-level times can use different modes, transfer locations, walking distances, or accessibility profiles.
2. Collapse only genuine duplicate/equivalent itineraries. Preserve useful alternatives while retaining stable positions and deterministic IDs.
3. Use the quality policy or explicit package recommendation metadata for `selectedOptionID`. `selectBestRouteOption` currently selects the first viable chronological option; `compareRouteOptions` is unused. Consolidate rather than adding a third ranking implementation.
4. Preserve manual selection through geometry updates, preference-compatible refreshes, and page merges. Re-select only when invalidated or when the user starts a new query.
5. Keep direct walking outside the five-transit-result budget without misusing the bike-only meaning of `supplementalOptions`; adjust the calculation model and comments coherently if needed.

### Acceptance

- A direct 08:00–08:30 trip survives alongside a one-transfer 08:01–08:29 trip.
- A route with two minutes of walking survives alongside one with fifteen minutes of walking and a small arrival advantage.
- A faster direct walk does not hide available transit.
- Equal displayed times do not erase distinct useful routes.
- Existing deterministic parallel-scan and refresh/geometry stability tests remain meaningful and pass.

## 6. Phase C — Validate walking refinement and transfer feasibility

### Work

1. Introduce a reusable itinerary validator and typed feasibility result. Place timetable-level rules in the package and app adaptation in the service layer; do not implement this in SwiftUI views.
2. Carry the original query anchor/direction, walking provenance, and required transfer time to the validation seam. `WalkingRouteRefining` currently receives only options; extend the contract or retain query context explicitly rather than consulting a mutable global clock or view-model state.
3. Rebuild walking times chronologically:
   - Access walk: work backward from the first boarding while retaining any configured boarding allowance; reject/replan if departure precedes the query's earliest departure.
   - Transfer walk: begin no earlier than the incoming vehicle's effective arrival, add actual walking duration, then check the outgoing boarding with the required transfer semantics.
   - Egress walk: begin at the last effective arrival; update final arrival and recheck an arrival deadline.
4. Preserve the distinction between physical walking and transfer allowance. Current `additionalTransferSeconds = max(0, transfer - transferWalkSeconds)` treats the transfer minimum as total interchange time. Keep feed rules and configured safety margins explicit, and test that a walk is neither counted twice nor allowed to consume a separately promised safety buffer unnoticed.
5. Recompute elapsed journey duration from final endpoints. Do not sum every walking-duration delta into total travel time: a longer interchange walk may consume waiting time without changing journey arrival or departure.
6. Populate structured transfer-feasibility/slack metadata and map it consistently into `RouteOption.status`. Existing string-based `transferWarning` must not be the only way newly invalid routes can be detected.
7. Evolve refinement output to carry invalidations/replacements as needed. `AsyncStream<RouteOption>` alone cannot cleanly remove an option. Reuse or extend `RouteCalculation.invalidatedOptionIDs`; ensure invalidated options cannot be resurrected by later transit-shape updates or accumulated page merges.
8. When refinement changes a decisive duration, perform a bounded replan using corrected walking costs in the engine/cache. Merely rerunning against the old cached matrix estimate repeats the error. Prevent unbounded refinement/replan loops and respect cancellation and request generations.
9. Preserve fallback provenance through `LocalFirstWalkingRoutingProvider`, which currently converts every walking result to package provider data without retaining the app's source distinction. An unreachable graph route and an unavailable routing dataset need different treatment; a straight-line fallback must not silently prove a tight connection feasible.
10. Handle partial matrix success per pair. One unreachable destination should not downgrade an entire useful local walking matrix to a straight-line fallback.

### Acceptance

- A transfer originally estimated at two minutes but refined to six never starts before the incoming vehicle arrives.
- If spare waiting absorbs that increase, vehicle times and total elapsed journey time remain unchanged.
- If it misses the outgoing vehicle, the route is invalidated and a feasible replacement is sought.
- Initial walking cannot require leaving before a depart-after request; egress cannot violate arrive-by unnoticed.
- Walking and shape updates arriving in either order preserve validation, geometry, identity, and the current request generation.

## 7. Phase D — Broaden transfer depth and improve candidate selection

### Transfer depth

1. Change the app's `preferences(_:)` mapping from one transfer to a documented default of three.
2. Keep direct and one-transfer options competitive via the quality policy. Do not spend all result slots on marginally faster multi-transfer variants.
3. Audit loops and repeated trip instances before increasing rounds. Prevent gratuitous alight/reboard or walking cycles while preserving legitimate loop-route travel and stop occurrences.
4. Preserve GTFS transfer prohibitions and minimums. Do not equate sharing a route number, block, or station with a guaranteed in-seat continuation.

### Endpoint candidates

1. Replace the nearest-24-only selection with a staged geographic shortlist diversified across station groups, service patterns, and modes. Retain individual platforms for actual boarding and walking calculations.
2. Prioritize stops with relevant active service in the query window; a dense cluster of inactive or redundant platforms must not exhaust the shortlist.
3. Measure shortlisted access/egress using the existing batched walking provider. Apply documented actual-walking budgets, then expand candidates when the first pass lacks sufficient or competitive results.
4. Keep explicitly selected origin-stop semantics: `journeyEndpoint(for:)` and its test deliberately preserve an exact stop. Distinguish selecting a parent station from selecting a specific platform; any station expansion must account for real access movement.
5. Preserve directional walking. Destination access must evaluate stop → destination, not reuse destination → stop where the network is asymmetric.

### Interchange candidates

1. Replace the unconditional same-parent exclusion in `nearbyTransferStops`. Use declared pathways first; when connectivity is missing, consider same-station pairs only with a verified physical route and applicable transfer rules.
2. Diversify the five-neighbour shortlist by useful onward services rather than just distance. Allow adaptive expansion beyond the current 450 m prefilter under an explicit walking-time budget when it unlocks a substantially better route.
3. Spend the current 96-request round budget on distinct stop pairs and useful connections. It currently counts label-specific requests before `WalkingRouteCache` coalesces them, so repeated arrivals at the same pair can consume the exploration budget.
4. Share static walking work across relevant labels without erasing time-dependent request semantics. Keep batching, bounded concurrency, cancellation, and cache behavior.
5. Record why a candidate was excluded or expansion stopped in internal metrics. Do not surface implementation details in ordinary route UI.

### Acceptance

- A bus → train → bus journey is discoverable and still respects an explicit one-transfer caller limit.
- A useful tram stop beyond 24 nearer redundant platforms remains discoverable.
- Same-station platforms without a feed pathway connect only when pedestrian evidence permits it.
- Unwalkable nearby stops do not become fictional shortcuts.
- Repeated labels do not starve a distinct interchange from the walking budget.
- More candidates do not trigger unbounded MapKit requests or a main-thread search.

## 8. Phase E — Implement arrival-deadline queries and correct paging

### Work

1. Add an explicit package query-time direction or equivalent query model. Preserve source compatibility for current `RouteQuery(departureTime:)` callers. The app must pass `.arriveBy` as a deadline, not subtract two hours.
2. Preferred design: implement a reverse/latest-departure search using reversed timetable traversal and correctly directed access/egress edges. Preserve pickup/drop-off eligibility, service-day overflow, realtime delays/cancellations, and transfer-rule direction; do not merely swap origin and destination in a forward query.
3. A staged forward-profile implementation is acceptable only if it evaluates an explicit, adaptively expanded departure window **before** truncating to five results, filters by final effective arrival, and returns the latest feasible departures within the documented horizon. It must not claim global completeness after a capped search or retain the current earliest-eight-label bias. Record this limitation if reverse search is deferred.
4. Make `calculateRoute` and `routeCalculationUpdates` share time/query construction so their behavior cannot diverge.
5. Recommend latest feasible door-to-door departure; break equivalent choices using quality policy. Late options may be offered only as clearly identified alternatives, never as satisfying the deadline.
6. Apply paging boundaries before page-size truncation. Current earlier-page code searches from boundary minus two hours, takes `session.initial(count:)`, then filters and takes a suffix; that cannot reliably return the nearest earlier departures.
7. Use a stable cursor or composite boundary if multiple variants share the same departure instant. A timestamp-only exclusive boundary can skip unseen alternatives at that timestamp.
8. Keep walking comparisons out of transit page boundaries. Preserve manual selection when earlier/later pages merge.
9. Ensure later pages for an arrive-by request continue to honor the original deadline. If no more feasible departures exist, report exhaustion without silently returning late arrivals. Align user-facing horizon text with actual search bounds.

### Acceptance

- For a 09:00 deadline, a feasible 08:35 departure wins over an 08:00 departure, even if more than five early departures exist.
- A required departure more than two hours before the deadline is found within the supported search horizon.
- A route arriving after 09:00 is not represented as on time.
- Midnight, service times beyond 24:00, and daylight-saving boundaries work with `ServiceInstantConverter` and service dates.
- Earlier/later paging returns adjacent feasible departures without duplicates or skipped same-time alternatives.
- Realtime and walking refinement can invalidate a previously on-time route and trigger reselection.

## 9. Phase F — Enforce mode and accessibility preferences

### Mode preference

1. Replace the 64-bit route-type representation with a lossless representation or normalization layer that supports extended GTFS types, including the tram range already handled by the app. Preserve `.all` and compatibility for existing basic-type callers/encoded settings where applicable.
2. Distinguish hard `allowedModes` from a preferred mode. App “train” preference should retain a useful bus → train → bus route.
3. Carry preferred-mode participation through candidate retention and ranking; apply it before the result limit. A preferred-mode route cannot be recovered by filtering five already-selected other-mode routes.
4. If no matching route exists within the evaluated search, return an explicit preference-relaxation outcome and use the existing closest-alternatives presentation coherently. Do not silently relax hard allowed-mode constraints.

### Accessibility

1. Load trip accessibility into `SnapshotTrip`; it is stored by the importer but absent from the routing snapshot. Preserve stop accessibility and include relevant pathway attributes currently discarded by `SnapshotPath`/snapshot loading.
2. Verify GTFS semantics against the official specification during implementation, particularly unknown values and parent-station inheritance. Do not guess inheritance rules or manufacture accessible status from missing data.
3. Introduce an explicit assessed state such as verified, inaccessible, or unknown, with enough provenance to explain the result. Whole-journey accessibility includes boarding, vehicles, alighting, station movement, and access/egress.
4. Implement `.required` as a hard constraint: known-inaccessible and unverified required segments cannot be advertised as verified accessible. Surface unavailable evidence honestly rather than silently falling back.
5. Map the app's “Prefer accessible options” to a soft preference: verified routes first, unknown alternatives labeled accurately, and known-inaccessible segments excluded from accessible recommendations. Remove the 700 m/one-transfer heuristic as a proxy for step-free access; walking burden can remain a separate preference.
6. Extend walking request profiles and cache keys if wheelchair routing is supported by the installed Valhalla/provider API. Verify actual provider capabilities; generic `.pedestrian` costing and straight-line estimates do not establish wheelchair feasibility. When support/evidence is absent, return unknown.
7. Ensure pathway direction, stairs, slope/width evidence, and known restrictions affect eligibility. Do not promise current elevator availability without a corresponding data source.
8. Update route-model mapping, minimal explanatory UI, localization, mocks, and previews as needed. Ensure post-search app filters do not override the new semantics.

### Acceptance

- A matching preferred-mode route survives beyond five nonmatching alternatives, including extended route types and mixed-mode access.
- A known-inaccessible vehicle or stairs-only required connection fails a hard wheelchair query.
- Unknown accessibility is never rendered as verified accessible.
- A longer step-free alternative is retained rather than pruned by a slightly faster inaccessible route.
- Generic pedestrian cache entries cannot satisfy wheelchair-profile requests incorrectly.
- Soft preference fallback is explicit; hard constraints are not relaxed by `applyRouteOptions`.

## 10. Suggested implementation sequence and integration

| Milestone | Scope | Exit condition |
|---|---|---|
| 1 | Baseline, fixtures, quality/feasibility contracts | Reproducible failing examples and agreed semantics |
| 2 | Package retention + app deduplication/selection | Useful tradeoffs survive end to end |
| 3 | Walking validation + invalidation/replan | Refined results remain catchable and internally consistent |
| 4 | Transfer depth + candidate selection | Two/three-transfer and station cases pass within measured budgets |
| 5 | Query direction + paging | Deadline and adjacent-page scenarios pass |
| 6 | Mode/accessibility enforcement | Preferences affect generation with honest evidence handling |
| 7 | Integration, benchmarks, documentation | App uses the tested package revision and all targeted checks pass |

Implement related package model changes early enough to avoid repeated incompatible app migrations. Keep coherent changes buildable and use focused commits where authorized; avoid mixing existing unrelated edits into those commits.

For local integration, use a reversible local package override/workspace setup and verify the app actually builds the modified checkout. Do not edit generated SwiftPM checkouts. Before delivery, restore a reproducible dependency configuration and identify the package commit needed by the app. If publishing the package commit or updating the remote pin is outside the current authorized workflow, leave the paired changes ready and explicitly report that integration step as pending; never claim the remote-pinned app includes uncommitted local package changes.

## 11. Required regression matrix

Use Swift Testing (`@Test`, `#expect`) with fixed clocks, temporary GTFS databases, and mock walking/realtime providers. Reuse [existing package fixtures][kit-tests] and [nearby-stop fixtures][nearby-tests]. Suggested new suite names below are proposals, not existing files.

| Scenario | Expected result | Test layer |
|---|---|---|
| Direct route loses one minute to a transfer | Both retained; policy chooses consistently | Package quality + app selection |
| Low-walk route loses a small amount of time | Both retained | Package dominance |
| Walking beats all transit | Walking comparison plus transit alternatives | Package + adapter |
| Same displayed minutes, different useful itineraries | Neither wrongly deduplicated | Existing [deduplication suite][dedup-tests] |
| Same-stop labels have different onward prohibitions | Feasible predecessor survives | Package transfer rules |
| More than eight early labels precede best deadline route | Latest feasible result survives | Package profile/arrive-by |
| Transfer walk grows but fits in waiting time | Same total elapsed journey duration | Existing [refinement suite][refine-tests] |
| Transfer walk grows beyond outgoing departure | Invalidated, no overlapping legs, replacement sought | Refinement + view model |
| Access refinement moves departure before query | Route rejected/replanned | Adapter |
| Egress refinement crosses arrival deadline | Route invalidated/reselected | Adapter + view model |
| Refinement arrives after a new query or invalidation | Stale result ignored | Existing [flow suite][flow-tests] |
| Bus → train → bus is only practical journey | Found with default; excluded with explicit maxTransfers=1 | Package + adapter |
| Dense redundant platforms hide useful 25th stop | Diverse shortlist finds useful service | Nearby-stop package suite |
| Same-parent platforms lack pathway | Verified pedestrian fallback only | Nearby-stop package suite |
| One matrix pair unreachable | Other pairs retain valid local estimates | Existing [offline walking suite][offline-tests] |
| Duplicate pairs consume probe budget | Distinct useful interchange still explored | Package budget tests |
| Arrive-by has many early departures | Latest on-time departure selected | Package + adapter |
| Journey needs more than two hours | Found within declared horizon | Package arrive-by |
| Midnight/overflow/DST | Correct service instant and deadline | Package time fixtures |
| Earlier page has many candidates | Nearest earlier results returned before truncation | Adapter paging |
| Same-time variants straddle page size | No skipped variants or duplicates | Package + adapter paging |
| Preferred mode appears after five other journeys | Matching route survives and is recommended | Package + app |
| Extended GTFS tram type | Correct allowed/preferred-mode behavior | Package mode tests |
| Inaccessible vehicle/pathway | Required query rejects; soft preference remains honest | Package accessibility |
| Missing accessibility evidence | Unknown remains unknown | Package + presentation |
| Generic pedestrian versus wheelchair cache | No cross-profile reuse | Walking cache/provider |
| Realtime delay creates/removes a connection | Search and refinement agree | Existing realtime fixtures |

Add a small exhaustive reference enumerator for tiny synthetic timetables, if needed, to compare supported query results against the optimized search without its heuristic budgets. Keep this test-only and bounded. It is especially useful for multi-criteria pruning, incoming-trip-specific transfers, and reverse queries.

## 12. Performance and execution checks

### Measure quality and cost together

Before and after each search change, record cold/warm time, candidate/label counts, pruned/truncated counts, walking requests/cache hits, maximum concurrency, and the returned journey set. Extend `RoutingMetrics` where necessary.

Use fixed regional fixtures covering a dense city interchange, a rural connection, a station transfer, and an arrival deadline. Include access/egress walking, not only stop-to-stop timing. Compare against a larger-budget or exhaustive small-fixture reference so better runtime cannot hide worse route recall.

Do not assert fragile wall-clock thresholds in unit tests. Set explicit request/label budgets in tests and report measured runtime changes separately. Reject unexplained large regressions; document any deliberate quality-versus-runtime tradeoff. Preserve cancellation, bounded network fallback, and responsiveness of the existing request-timeout flow.

### Commands

Verify available tooling and destinations first:

```sh
cd /Users/REDACTED/Developer/Verkeier
xcodebuild -list -project Verkeier.xcodeproj -disableAutomaticPackageResolution
xcodebuild -showdestinations -project Verkeier.xcodeproj -scheme Verkeier -disableAutomaticPackageResolution
```

Run deterministic package regressions while excluding the existing network-dependent archive test:

```sh
cd /Users/REDACTED/Developer/MobilitéitKit
swift test --skip gromscheedToHamiliusAppRoutePrintsRealGTFSResults
```

Confirm the installed SwiftPM runner's filtering support. Keep the network-dependent test separate from required offline checks. New tests must not depend on live feeds.

Build and test the app using an actual installed simulator UUID from `-showdestinations`:

```sh
cd /Users/REDACTED/Developer/Verkeier
xcodebuild -project Verkeier.xcodeproj -scheme Verkeier \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UUID>' \
  -disableAutomaticPackageResolution build

xcodebuild -project Verkeier.xcodeproj -scheme Verkeier \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UUID>' \
  -disableAutomaticPackageResolution test \
  -only-testing:VerkeierTests/WalkingRouteRefinementTests \
  -only-testing:VerkeierTests/RouteOptionDeduplicationTests \
  -only-testing:VerkeierTests/OfflineWalkingRoutingTests
```

Run new suites and deterministic flow tests as well; the sample targeted command is not the complete acceptance gate. Inspect the existing real-feed app test before running the full flow suite. Run the broader app suite after the focused checks, separating environmental/live-feed failures from deterministic regressions. Verify package integration before interpreting results.

Manually inspect one fixture-driven route sheet for each query direction: recommendation, alternatives, walking duration, transfer warnings, accessibility uncertainty, earlier/later paging, and selection persistence after refinement. Verify VoiceOver labels and Dynamic Type for any new status text.

## 13. Completion checklist and agent report

- [ ] All six review findings implemented across package and app.
- [ ] No source path still applies the old one-transfer cap, two-hour arrive-by approximation, time-only alternative elimination, or walking-distance-as-accessibility heuristic in the affected flow.
- [ ] Intermediate pruning and app deduplication preserve the final quality contract.
- [ ] Walking refinement validates against the original query and cannot resurrect invalid routes.
- [ ] Hard constraints, soft preferences, unknown evidence, and search-budget exhaustion are distinguishable.
- [ ] Primary transit slots, walking comparison, bike alternatives, and page boundaries remain coherent.
- [ ] Deterministic regression matrix covered, relevant existing tests updated intentionally, and builds pass.
- [ ] Performance/quality comparisons recorded with fixture identities and budgets.
- [ ] Paired package/app revisions and actual dependency integration verified or clearly reported pending.
- [ ] Documentation for preferences, query direction, and service/refinement contracts updated.
- [ ] Unrelated working-tree changes preserved.

The final implementation report must identify behavior changes, key design decisions, files/commits, test commands/results, representative before/after journeys, measured performance impact, and any remaining limits. Do not describe a partially implemented phase as complete merely because existing tests pass.

## Source references

These links point to the checked-out files used for this plan. Locate symbols again if source moves.

[claude]: /Users/REDACTED/Developer/Verkeier/CLAUDE.md
[rules]: /Users/REDACTED/Developer/Verkeier/docs/CODEBASE_RULES.md
[services]: /Users/REDACTED/Developer/Verkeier/docs/SERVICES.md
[project]: /Users/REDACTED/Developer/Verkeier/Verkeier.xcodeproj/project.pbxproj
[resolved]: /Users/REDACTED/Developer/Verkeier/Verkeier.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
[app]: /Users/REDACTED/Developer/Verkeier/Verkéier/App/VerkéierApp.swift:29
[router]: /Users/REDACTED/Developer/MobilitéitKit/Sources/MobilitéitKit/Routing/TransitRouter.swift
[walk-cache]: /Users/REDACTED/Developer/MobilitéitKit/Sources/MobilitéitKit/Routing/WalkingRouteCache.swift
[importer]: /Users/REDACTED/Developer/MobilitéitKit/Sources/MobilitéitKit/GTFSArchiveInstaller.swift
[adapter]: /Users/REDACTED/Developer/Verkeier/Verkéier/Services/Routing/MobiliteitRouteService.swift
[route-service]: /Users/REDACTED/Developer/Verkeier/Verkéier/Services/Routing/RouteService.swift
[local-walking]: /Users/REDACTED/Developer/Verkeier/Verkéier/Services/Routing/LocalFirstWalkingRouter.swift
[walking]: /Users/REDACTED/Developer/Verkeier/Verkéier/Services/Routing/WalkingRouting.swift
[valhalla]: /Users/REDACTED/Developer/Verkeier/Verkéier/Services/Routing/ValhallaWalkingRouter.swift
[view-model]: /Users/REDACTED/Developer/Verkeier/Verkéier/Features/Map/ViewModels/TransitMapViewModel+RoutePlanning.swift
[option]: /Users/REDACTED/Developer/Verkeier/Verkéier/Models/RouteOption.swift
[plan]: /Users/REDACTED/Developer/Verkeier/Verkéier/Models/RoutePlan.swift
[calculation]: /Users/REDACTED/Developer/Verkeier/Verkéier/Services/Routing/RouteCalculation.swift
[planner-models]: /Users/REDACTED/Developer/Verkeier/Verkéier/Models/RoutePlannerModels.swift
[kit-tests]: /Users/REDACTED/Developer/MobilitéitKit/Tests/MobilitéitKitTests/MobilitéitKitTests.swift
[nearby-tests]: /Users/REDACTED/Developer/MobilitéitKit/Tests/MobilitéitKitTests/NearbyStopRoutingTests.swift
[dedup-tests]: /Users/REDACTED/Developer/Verkeier/VerkéierTests/RouteOptionDeduplicationTests.swift
[refine-tests]: /Users/REDACTED/Developer/Verkeier/VerkéierTests/WalkingRouteRefinementTests.swift
[flow-tests]: /Users/REDACTED/Developer/Verkeier/VerkéierTests/RouteCalculationFlowTests.swift
[offline-tests]: /Users/REDACTED/Developer/Verkeier/VerkéierTests/OfflineWalkingRoutingTests.swift
