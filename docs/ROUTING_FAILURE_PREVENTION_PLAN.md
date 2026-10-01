# Routing failure prevention plan

Prepared 1 October 2026 from the user's 49-case routing checklist. This is a source audit and implementation plan; it does not implement the proposed safeguards or certify that every case is prevented today.

## Goal and boundaries

Prevent impossible journeys from reaching the UI, remove demonstrably wasteful choices, and return useful, stable alternatives. Every checklist case has an acceptance scenario below. Fix the search and package result lifecycle first; app-only filtering cannot recover good routes pruned during search.

Some examples describe suspicious journeys rather than universally invalid ones. A circular bus may legitimately visit a stop twice; a useful interchange may require travelling away from the destination; two different vehicles on line 16 may form the best connection. Preserve these when justified by timetable, physical access, constraints, and a material benefit. Never use route number, `direction_id`, distance to destination, or repeated stop name alone as a rejection rule.

The user's walking policy supersedes the older [route quality plan](ROUTE_QUALITY_IMPLEMENTATION_PLAN.md): a verified 15-minute direct walk should become the recommendation over a 25-minute two-bus journey when walking is eligible for this request. Do not hide necessary accessible transit or a materially lower-walking choice. Keep any explicit preference for transit meaningful.

No backend, account system, new live-data contract, or UI redesign is required. Policy stays in MobiliteitKit; Verkéier adapts results and presents their meaning through its existing service and view-model layers.

## Audited baseline

Both repositories were clean before this documentation change:

- Verkéier: `34813be` (`Move departure sharing into stop navigation menu`).
- MobiliteitKit: `4ba6e7d7f77fdd2a41f8ad27ef24d9c54afcf9c4`, also the app's resolved dependency revision.
- The local package is `/Users/pedoataidecordeiro/Developer/MobilitéitKit`. Edit that repository, then integrate its tested revision; do not create another package copy inside the app.
- `graphify-out/` is absent in this checkout. Source symbols below provide the implementation map.

Verified during this audit:

- Simulator build succeeded for the `Verkeier` scheme on iPhone 17.
- Offline package run passed **91 tests in eight suites**, with `ROUTING_VERIFY_KERNEL=1`. The network-downloading test and installed-feed benchmarks were excluded explicitly. Passing this baseline does not prove the 49-case matrix.
- App suite passed **42 tests in nine suites** on the iPhone 17 simulator with code coverage disabled.

### Existing safeguards to retain

| Area | Current source and evidence | Limit of the evidence |
|---|---|---|
| Reboarding a trip | `RaptorCompactScan` and `RaptorReferenceScan` reject an instance already in `source.tripKey`, keyed by trip and service day | Add a dedicated regression; this does not track complete journey stop cycles |
| Stop occurrence order | Scanners only alight at positions after boarding; keys contain occurrence positions | Public `TransitLeg` lacks explicit service-day/sequence identity; adapter leg IDs use stop IDs |
| Time feasibility | `JourneyItineraryValidator` checks anchors, negative duration, overlapping legs, transfer walking evidence and slack | It is a timing projection, not a complete topology/calendar/constraint validator |
| Dominance and ranking | `JourneyQualityPolicy`, `strictEnvelope`, 300-second transfer penalty, additional walking burden | No explicit independent-first-vehicle diversity or recommendation hysteresis |
| Duplicate transfer variants | `sameVehicleChoice`, `equivalentTransferKey`, `prefersSaferTransfer` | Grouping retains first/last stop identity; endpoint entrance variants need separate treatment |
| Realtime eligibility | Cancelled/unreachable instances excluded; delayed scheduled-past boardings and delay-created transfers tested | Partial evidence, propagation limits, and third-party sparse patches still need end-to-end safety tests |
| Calendars and dates | Active service-day sets; noon-based `ServiceInstantConverter`; overflow, midnight and DST fixtures | Add consecutive-service-day and linked-trip regressions |
| Walking cycles | `walkingStopsVisited` prevents repeats within a pedestrian chain | It resets after a transit leg; it is not a journey-wide cycle policy |
| Accessibility and modes | Allowed modes enforced during scan; required wheelchair evidence checked during construction | App exposes a soft mode preference and tight-transfer toggle, not hard mode exclusions or a step-free request |
| Refinement and lifecycle | Package validates refinement, invalidates unsafe choices, replans once, guards generation/fingerprint | Structural rules must also run here and at every publication |
| Paging | `(departure, journey ID)` boundary; accumulated ID merge; equal-departure cursor test | Live-changing boundaries, selected noncontiguous initial results and repeated paging need broader coverage |

### Confirmed gaps in current code

1. `RoutingPreferences.init(preferredMode:avoidTightTransfers:)` permits up to 180 seconds of generic same-stop shortfall by default. Existing tests deliberately accept a below-minimum transfer as `.atRisk`. Under this checklist, published/user minimums must be strict; a warning cannot authorize violating them.
2. Production search has no continuation leg in `Raptor.Leg`; `SnapshotTrip` does not retain block identity. Transfer type 4 currently shares the zero-allowance branch with type 1 and becomes an ordinary second ride. Public continuation types and a manually constructed summary test do not establish production through-service support.
3. `MobiliteitRouteService.option` drops `.inSeatContinuation`. `RouteTimelineBuilder` labels adjacent transit rides as a transfer. Continuation meaning would be lost even after package search starts producing it.
4. Transfer rules are indexed by station groups, but `transferDecision.applies` only checks trip/route scope. It does not recheck exact rule endpoints. A platform-specific rule can consequently affect another platform in the same parent station.
5. `SnapshotTime` does not retain imported `stop_headsign`; journey construction always uses the trip headsign. Boarding-specific headsign changes cannot be represented.
6. `primaryProfile` chooses a recommended route plus chronological fillers without independent-first-vehicle selection. Five permutations of one fragile first bus are possible unless other pruning happens to remove them.
7. Both `makePage` and `JourneyResultSession.snapshot` recommend from transit first. A faster walking comparison cannot win while transit remains.
8. A journey-wide structural/cycle validator and a refresh stability policy are absent. These are coverage gaps, not evidence that every suspicious journey currently occurs.

## Behavior contract

### Strict validity

Validate a canonical itinerary against the immutable feed generation and query preferences, including after realtime overlay and walking refinement:

- Identity: trip instance = feed generation + trip ID + GTFS service date + frequency instance where applicable. Stop occurrence = that instance + `stop_sequence`/position. Route number and stop name are display metadata.
- Every transit occurrence must exist, operate that service day, allow the requested boarding/alighting, and have boarding position strictly before alighting position.
- All leg timestamps must exist and be chronological. Match intermediate events, scheduled times and effective times to the same instance. Zero duration is allowed only where the feed/verified topology supports it; a positive physical movement cannot be instantaneous.
- Adjacent locations must connect physically. Different child stops need declared pathways or a verified pedestrian route; shared `parent_station` alone proves no movement time or accessibility.
- Enforce all hard mode, transfer-count, walking-budget and accessibility requirements during generation and again at publication. Soft preferences remain preferences; unknown accessibility cannot satisfy “required.”
- Reject cancellation, forbidden transfers, unverified transfer movement, missed minimums and stale/contradictory prediction evidence used to prove an otherwise uncatchable connection.
- Only a verified continuation exempts a connection from alighting/reboarding minimums. Its linked trips and times must themselves be valid.

### Transfer arithmetic

Keep physical movement, published total interchange minimum, user total minimum, and any separately configured boarding buffer as separate fields. With incoming arrival `A`, outgoing departure `D`, physical movement `W`, total minima `F` and `U`, and a separately additive buffer `B`:

```text
required total interchange = max(F, U, W + B)
slack = D - A - required total interchange
valid actual transfer iff slack >= 0
```

GTFS minima already describe the total interchange, so do not add the whole minimum to walking again. `requiredTransferSecondsAfterWalking` must encode `max(0, requiredTotal - W)` consistently in scan, validator and refinement. Recalculate it when `W` changes. Feed timed-transfer semantics require explicit handling; they cannot create overlapping legs or erase physical walking. Preserve a caller's promised minimum unless a verified stay-aboard continuation makes it inapplicable.

Set production shortfall tolerance to zero. A “tight” label may describe a valid transfer with little surplus slack; it must never convert negative slack into a selectable result. Add exact-boundary tests at one second below, equal to, and one second above the minimum, including fractional timestamps.

### Avoidable waste and legitimate exceptions

Use three distinct decisions:

1. **Invalid:** impossible timing, forbidden actions or violated hard constraints. Never publish.
2. **Redundant:** the same action sequence, an unnecessary reboard, or a removable cycle for which a feasible simpler journey is no worse. Collapse or suppress.
3. **Tradeoff:** extra walking, detour, transfer or wait buys meaningful arrival, departure flexibility, accessibility, mode preference or resilience. Keep only useful representatives.

Exact dominance compares departure, arrival, transfers and walking with compatible accessibility/preference evidence. Keep later departures that remain useful to riders who cannot catch the earlier service. Apply a separate material-benefit policy to near-equivalent choices; do not corrupt search feasibility or exact Pareto dominance with a heuristic.

Initial calibration uses the existing 300-second transfer penalty and walking burden. Add named, injectable thresholds: 120 seconds of arrival benefit for collapsing near-equivalent suggestions, and at most two suggestions sharing a first trip instance when competitive independent choices exist. These are proposed presentation-policy values to validate against fixtures and installed-feed samples, not GTFS rules. The direct-versus-three-transfer one-minute case and 1.5 km walk to save two minutes must prefer the easier journey and avoid crowding the main list. If no easier eligible route exists, retain the only feasible route rather than reporting no service.

## Implementation sequence

### A — Establish canonical identity and strict publication validation (highest priority)

Owner: MobiliteitKit `TransitRouter`, `RaptorPreparation`, both scanners, `JourneyAssessment`, `JourneyPlanningTypes`, `JourneyResultSession`; app preference adapter and route-model mapping.

1. Add instance/occurrence identity and boarding-specific headsign to public transit legs compatibly. Keep stable signatures independent of realtime/geometry. Propagate identity into the app; qualify presentation leg IDs by instance and occurrence.
2. Add a separate structural validator that can inspect the immutable snapshot and query. Keep the lightweight timing validator for persisted/fixture presentation models; do not pretend it can prove calendars or pickup permissions without that context.
3. Fix exact stop scope and specificity for transfer rules after station-group lookup. Parent-station rules may expand to children; a child-specific rule must remain child-specific. Keep trip/route restrictions and deterministic precedence.
4. Make minima strict, unify transfer arithmetic, and validate pathway durations/positive movement. Carry typed rejection reasons for identity, occurrence, topology, calendar, permissions, constraints and evidence failures.
5. Run validity checks before representative selection/dominance, on final search results, after every realtime/refinement change and before each session snapshot. An invalid route must never suppress a valid one.
6. Reject invalid imported trips/pathways or quarantine the affected entities with a diagnostic; preserve the last usable installed feed when an update fails. Never silently repair corrupt feed times into plausible journeys.

Acceptance: cases 11–13, 25–28, 37, 40–47, with boundary fixtures and an unchanged valid control in each category.

### B — Remove redundant cycles and endpoint choices

Owner: package candidate construction, `RaptorTypes`, `RaptorDominance`, both scan kernels, `RaptorWalkingTransfers`; new small pure canonicalization/quality helpers in the package routing folder.

1. Retain the trip-instance reboard guard and test it explicitly. Canonicalize adjacent pieces of the same instance into one ride when contiguous and permitted; never instruct a rider to exit and reboard unnecessarily.
2. Detect repeated boarding/alighting station occurrences across the full journey and zero-movement transfer cycles. Compare a cycle-free candidate or shortcut against the original, including departure time, accessibility, transfer rules and incoming-trip continuation eligibility. Prune only when the shortcut is demonstrably valid and no worse.
3. Keep walking-chain visit state and reject zero/negative-cost movement. Station grouping is useful for equivalence, not for replacing child platforms in feasibility.
4. Compare staying aboard to every proposed transfer and compare feasible earlier/later boarding or alighting occurrences on the same instance. Suppress changes that add burden without material benefit. Do not rewrite an itinerary from coordinates alone.
5. Canonicalize entrance/platform variants only after checking physical routes, same trip occurrence, timing and accessibility. Pick the simplest eligible representative deterministically; retain materially different choices.
6. Preserve future eligibility when pruning search labels. If journey-history state changes, update both compact and reference representations plus dominance/eviction guards together. A final filter must not be the only protection.

Acceptance: cases 1–10, 17–18, 20–21, 38–39. Negative controls include a legitimate circular ride, a necessary detour around a barrier, a later different vehicle on the same line, and a useful reverse-direction interchange.

### C — Implement verified stay-aboard continuations end to end

Owner: GTFS snapshot/import contract, search state/round accounting, canonical validator, summaries; app adapter, `RoutePlan`, timeline model, share text and VoiceOver descriptions.

1. Retain linked-trip transfer types 4/5 and the data necessary to evaluate them. Type 4 permits staying aboard; type 5 requires alighting/reboarding. Explicit linked-trip rules take precedence over conflicting block information. Same route number or block ID alone must not generate a promise that passengers can remain seated. Follow the [GTFS reference](https://gtfs.org/documentation/schedule/reference/#transferstxt).
2. Only add continuations between eligible trip instances with compatible service dates, endpoint topology and chronology. Handle cross-midnight links and cancellation of either portion. If local feed evidence is insufficient, record a TODO for a verified source contract and show an ordinary valid transfer instead of inventing through-service.
3. Count actual vehicle changes separately from transit segments. Continuing on the same vehicle must not consume transfer allowance or penalty. Search must be able to find a linked two-segment ride with `maxTransfers = 0`.
4. Emit explicit continuation metadata; preserve route-number changes. App presentation must say “Stay aboard” and never show “get off/change/board” at that boundary. Keep summary, timeline, sharing and accessibility speech consistent.

Acceptance: cases 22–23 plus zero-transfer, prohibited-continuation, cross-service-day, and cancelled-continuation fixtures. An unrelated same-block trip must not be fused automatically.

### D — Choose useful recommendations and independent alternatives

Owner: `JourneyQualityPolicy`, `primaryProfile`, `makePage`, `JourneyResultSession.snapshot`; app consumes package recommendation and ordering.

1. Keep exact multidimensional dominance and add tested material-benefit suppression for main suggestions. Include walking burden, actual transfers, waiting burden and valid uncertainty; large slack has capped benefit.
2. Compare verified direct walking against transit using the request's eligible modes, walking budget and accessibility. For the 15-versus-25-minute case, recommend walking; suppress strictly worse transit from main suggestions when it offers no meaningful reduction in walking or preferred-mode/accessibility benefit. If product presentation exposes additional transit choices, make that deliberate rather than selecting a bus by default.
3. Select the best eligible recommendation first, then useful lower-transfer/lower-walking choices, then independent first-trip fallbacks. A fallback must be catchable after missing the first option, accounting for its boarding location and access walk. Different downstream transfers off the same first bus do not count as independent.
4. Prefer an independent fallback within the documented quality envelope. Do not force diversity by showing a terrible route, fabricate options, or hide the only practical shared-first-vehicle choices. Return fewer than five when fewer useful choices exist.
5. Keep chronological browsing, but order equal/near-equal departure choices by arrival and quality. The recommended option must be clear even if a chronologically earlier route appears first. Never put a 55-minute journey above a 30-minute one at the same departure and comparable burden merely because its ID sorts first.

Acceptance: cases 6–10, 14–21, 34–36. Test the exact examples, both depart-after and arrive-by, with and without a transit/accessibility preference.

### E — Harden realtime evidence and stabilize refresh

Owner: `HafasRealtimeRoutingProvider+Events/+Matching/+Acquisition`, `RealtimeTripPatch+Merging`, `RaptorPreparation`, realtime discovery, `JourneyResultSession`.

1. Validate the complete effective trip timeline, including scheduled fallback events omitted by sparse patches, not only events present in the patch. Check arrival-before-departure at each occurrence and monotonic progression between occurrences.
2. Define one bounded propagation policy using observation time, occurrence, progression and timing source. Missing downstream reports must not silently reset a known +15-minute delay to an on-time claim. If propagation expires, mark downstream uncertainty or fall back coherently; reject contradictory patches without retaining their catchability advantage.
3. Treat estimated predictions as uncertain. Use conservative timing bounds to prove delay-enabled boarding/transfer feasibility; an expired upstream observation must not prove that a vehicle is still approaching. Fresh direct observations can prove newly catchable departures. Preserve scheduled/reported/estimated distinctions in app output.
4. Keep the delayed-past lookback and onward realtime discovery tests, including delayed transfers absent from scheduled winners. Record exhausted acquisition/search coverage honestly; incomplete coverage is not proof that no better route exists.
5. Keep cancellation and skipped-stop permission changes authoritative. Unmatched/ambiguous records cannot invent a trip or revive one removed from the current feed generation. Never treat missing realtime as cancellation.
6. Separate exact effective times used for safety from recommendation/display stability. Retain stable IDs and manual selection while valid. Introduce a session-level switching margin (proposed 60 seconds of quality score improvement) for near-equal recommendations; switch immediately on invalidation, cancellation, hard preference changes or a material benefit. Do not bucket timestamps before feasibility checks.
7. Add shifted-anchor metamorphic tests: at +60 seconds, still-catchable unchanged trips remain consistent; changed results are explainable by a missed departure, service window, preference or new evidence. Cache/budget changes must not cause nondeterministic tie-breaking.

Acceptance: cases 27–33, 37, 44, 48; test sparse, fresh, stale, contradictory and out-of-order patches with an explicit clock and no network.

### F — Make pagination and async publication coherent

Owner: `JourneyResultSession.resolved/makeQuery/merge/snapshot`, package bounded pages, app page/refinement orchestration.

1. Use stable query/feed/realtime-generation-qualified cursors with `(effective departure, stable signature)` ordering. Earlier/later applies to chronological departures; arrive-by pages must still meet the arrival deadline. Document that the app receives an accumulated snapshot rather than treating every returned option as newly paged content.
2. Track page exploration boundaries separately from the min/max of selected suggestions. A recommended initial choice may be outside the chronological prefix; paging must not skip valid choices between selected results. Expand/backfill a page after validation/deduplication removes entries until it contains new useful choices or the search budget is exhausted.
3. Within a fixed generation, earlier additions are strictly before their cursor and later additions strictly after it, including equal timestamps ordered by ID. Alternate earlier/later repeatedly without duplicating or losing journeys. Existing accumulated rows may remain visible; that is not page overlap.
4. On realtime/feed changes, either rebase cursors and accumulated results atomically or invalidate them and start a new generation. Never mix boundaries from one snapshot with timings from another silently.
5. Preserve invalidations across geometry/refinement/paging callbacks. Old requests, stale feed generations and cancelled tasks must not resurrect removed options. Preserve a valid manual selection; fall back to the package recommendation when it becomes unusable.

Acceptance: cases 9–10, 33, 48–49 plus equal-time cursors, changing delays, arrive-by paging, noncontiguous initial selection and interleaved stale callbacks.

## Complete checklist coverage

Status legend: **Existing** = a safeguard/test exists, but the acceptance below still needs dedicated proof; **Partial** = relevant checks exist but do not cover the entire case; **Gap** = an explicit guard or policy is missing; **Conflict** = current intended behavior permits the example. These are source-audit classifications, not claims that production reproductions have been observed.

| # | Checklist case | Status | Phase and required regression |
|---|---|---|---|
| 01 | Same vehicle used twice unnecessarily | Existing | B: same trip/service-day cannot be boarded twice; different trip instance on the same line remains eligible |
| 02 | Backtracking | Gap | B/D: A→B→C→B→D loses to the feasible shortcut; retain a necessary detour where shortcut is forbidden |
| 03 | Same line in opposite directions | Gap | B/D: suppress an avoidable reversal; retain a beneficial permitted connection; use occurrence order, not `direction_id`, for validity |
| 04 | Loops | Partial | B: remove a removable inter-leg cycle; keep a legitimate single circular ride and correct repeated-stop occurrences |
| 05 | Getting off and immediately reboarding the same service | Existing | B: contiguous same-instance segments become one ride; prohibit unnecessary reboard in both scan kernels |
| 06 | Pointless transfers | Partial | B/D: staying aboard reaches the destination as well or better; the extra transfer is absent from main suggestions |
| 07 | Transfer to a slower vehicle | Partial | B/D: staying aboard arrives 10:20; transfer arrives 10:25; discard when no material preference/accessibility advantage |
| 08 | Dominated itineraries | Existing | A/D: 10:00–10:30 dominates 09:55–10:35 at equal burden; a genuine less-walking alternative survives |
| 09 | Duplicate routes | Partial | B/F: identical instance/occurrence/actions appear once across search, refresh, refinement and page accumulation |
| 10 | Tiny variations presented as separate alternatives | Partial | B/D: 20 m entrance variations collapse; inaccessible versus accessible entrances do not collapse blindly |
| 11 | Impossible transfers | Conflict | A: 10:04:50 arrival and 10:05 departure fails a 120-second minimum, regardless of warning or shared parent |
| 12 | Negative or zero-duration transfers that aren't valid | Partial | A/C: negative gap rejected; zero physical platform change rejected; valid verified continuation remains allowed |
| 13 | Unrealistically tight transfers | Conflict | A: negative configured/feed slack is never selectable; exactly meeting the minimum is valid and may be labelled tight |
| 14 | Excessively long transfer waits | Partial | D: 45-minute wait loses to an eligible later/direct choice with comparable arrival and less burden; retain sole rural service |
| 15 | Absurdly early departure | Existing | D: 08:40–09:00 replaces 08:00–09:00 at equal burden; arrive-by recommends latest feasible door-to-door departure |
| 16 | Excessive number of transfers | Partial | D: three changes saving one minute do not crowd out or outrank a direct service; configured max is still hard |
| 17 | Walking backwards | Gap | B/D: needless away-and-back access loses to nearby boarding; barrier-required or materially faster walking detour survives |
| 18 | Huge walking leg for negligible benefit | Partial | D: 1.5 km to save two minutes loses to eligible 100 m access under default quality policy |
| 19 | Transit route worse than walking | Conflict | D: eligible verified 15-minute walk becomes recommendation over 25-minute two-bus route; required access evidence remains strict |
| 20 | Boarding at an obviously inferior stop | Partial | B/D: walking past a nearby eligible occurrence of the same trip adds no benefit and is suppressed; pickup prohibition is respected |
| 21 | Alighting before the useful stop | Partial | B/D: one-stop-early egress loses when staying aboard is easier and no later; earlier exit that genuinely saves time survives |
| 22 | Missed through-service | Gap | C: real linked type-4 journey found with zero actual transfers, even when its route number changes |
| 23 | Treating a vehicle continuing through a stop as a transfer | Gap | C: summary, timeline, sharing and VoiceOver say stay aboard; type-5 link still requires boarding again |
| 24 | Wrong direction / destination headsign | Partial | A/C: boarding-specific headsign retained; identity and ordered stop sequence determine eligibility; no invented headsign |
| 25 | Boarding after the destination | Existing | A: reject boarding position ≥ alighting position in canonical output, scan and refinement validation |
| 26 | Using the wrong occurrence of a repeated stop | Existing | A/E: circular trip's two identical stop IDs remain distinct by sequence and service date through realtime and adapter |
| 27 | Chronologically impossible legs | Existing | A/E/F: walk ends 10:10, vehicle starts 10:08; reject after generation and every update; stale callback cannot restore it |
| 28 | Realtime creates impossible teleportation | Partial | A/E: sparse departure-only +15-minute patch cannot leave an earlier downstream arrival or negative dwell/travel duration |
| 29 | Realtime delay applied inconsistently along a trip | Partial | E: propagate bounded +15 minutes consistently; a fresh report may show recovery; missing report cannot imply recovery |
| 30 | Ignoring a delayed catchable vehicle | Existing | E: scheduled five minutes ago, fresh prediction five minutes ahead remains catchable after actual access walking |
| 31 | Ignoring a transfer made possible by delay | Existing | E: delay-created valid connection survives discovery and final scan; test beyond the scheduled top choices |
| 32 | Assuming a delayed connection is catchable when it isn't | Partial | E: expired observation at another stop cannot prove catchability; fresh local evidence changes eligibility correctly |
| 33 | Excessive route churn from realtime | Gap | E/F: 10–20-second noise preserves IDs/manual selection and near-equal recommendation; actual miss switches immediately |
| 34 | Results aren't ordered sensibly | Partial | D: equal departure/comparable burden puts 30-minute option before 55-minute option and selects it |
| 35 | Alternative results aren't actually alternatives | Gap | D: reserve a competitive fallback with a different first trip instance rather than five first-bus permutations |
| 36 | No resilience between displayed options | Gap | D: fallback can still be reached after the first vehicle is missed; do not fabricate independence when none exists |
| 37 | Route requires catching two vehicles simultaneously | Partial | A/E: one canonical itinerary has no overlapping rides; each alternative is independently valid, not combined with another |
| 38 | Repeated transfer stop without movement | Partial | B: A→X→B→X→C zero-movement cycle is suppressed when redundant, with occurrence/continuation exceptions tested |
| 39 | Station-complex abuse | Partial | A/B: platform cycling cannot improve a label or consume free movement; child rules do not leak across the station |
| 40 | Unreasonable station transfers | Partial | A: 500 m child-platform move consumes verified time even with common parent; unreachable/unknown movement cannot prove transfer |
| 41 | Ignoring service calendars | Existing | A: weekly rules plus added/removed dates applied before overlay; wrong-day live record cannot activate absent service |
| 42 | Mixing service days incorrectly | Existing | A/C/E: 25:10 belongs to previous service date; same trip ID on consecutive dates and linked midnight trips stay separate |
| 43 | Bad midnight ordering | Existing | A/E: 23:58→00:06 resolves to increasing absolute instants; preserve overflow and both DST transition cases |
| 44 | Phantom trips | Existing | A/E/F: cancellation/removal invalidates every boarding occurrence and continuation; subsequent stale pages cannot revive trip |
| 45 | Wrong pickup/drop-off behavior | Existing | A/E: no boarding at `pickup_type=1`, no exit at `drop_off_type=1`; skipped-stop patch suppresses just that occurrence |
| 46 | Uses inaccessible transfers despite accessibility requirements | Existing | A/C: required step-free rejects stairs/unknown vehicle or walking access; soft preference remains visibly uncertain |
| 47 | Ignores user constraints | Partial | A/D: hard max transfers, minimum, allowed modes and access requirements hold through search and refinement; app soft mode labels stay truthful |
| 48 | Very unstable results | Partial | E/F: +60-second anchor preserves still-catchable alternatives unless a documented eligibility/quality boundary changes |
| 49 | Earlier/Later pagination overlaps badly | Partial | F: 20 alternating pages, equal-time departures, shifted realtime and arrive-by deadline produce unique accumulated rows and strict new boundaries |

## Verification and delivery gates

1. Add deterministic small GTFS fixtures beside the existing Swift Testing suites. For every row above, add a named positive assertion and the important legitimate exception. Keep a case-ID-to-test map so “covered” is reviewable. Mock walking and realtime with explicit clocks and temp databases; no live network in ordinary tests.
2. Add generated-fixture/property checks for occurrence order, active service, nonnegative timeline, physical adjacency, strict minimums, no repeated trip instance, hard preference compliance, unique signatures and page progress. Compare against an exhaustive solver on tiny networks for soundness and retained useful choices; replaying the same broken rule in a test is insufficient.
3. Run compact/reference differential verification after every search-state or pruning change. Differential equality proves compatibility between kernels, not correctness of a shared policy, so retain the independent tiny-network oracle.
4. Add app integration tests for continuation mapping, timeline/share/VoiceOver meaning, authoritative snapshots, manual selection, invalidation, faster walking selection and stale async updates. UI remains previewable with fixture services.
5. Replay installed-feed journeys without downloading data during the test run: urban, rural, circular, multi-transfer, platform changes, both directions, depart-after, arrive-by, midnight, first/last service, recorded delay and cancellation. Compare quality invariants and explanations as well as exact IDs.
6. Retain the existing Release rendered-result p95 target of five seconds from [the performance plan](ROUTE_CALCULATION_PERFORMANCE.md), with the same warm/cold and full realtime-budget methodology. Record memory and truncation/coverage counters; a quality filter must not conceal search exhaustion or make the router unbounded.
7. Publish only valid results, and return an honest empty/error/partial result when nothing passes. Add bounded diagnostic counters for rejection reasons, duplicate/cycle suppression, shared-first-trip groups, recommendation switches and page progress. Use local opt-in diagnostics, not new remote telemetry; never log keys or precise personal journeys by default.
8. Deliver focused milestones: strict validity → cycles/endpoints → continuations → choice policy → realtime stability → paging. Each milestone needs passing fixtures, package tests and app integration before updating the app's remote package pin. Record known uncovered cases; do not mark all 49 complete solely because the existing suite is green.

### Reproduction commands

```sh
# In the MobiliteitKit checkout: explicit offline exclusions for the current baseline.
ROUTING_VERIFY_KERNEL=1 swift test \
  --skip 'gromscheedToHamiliusAppRoutePrintsRealGTFSResults|installedFeed|InstalledTimetableBenchmarkTests'

# In Verkéier.
xcodebuild -project Verkeier.xcodeproj -scheme Verkeier \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -project Verkeier.xcodeproj -scheme Verkeier \
  -destination 'platform=iOS Simulator,name=iPhone 17' -enableCodeCoverage NO test
```

Follow-up test hygiene: convert the package's unconditional live-download test to a deterministic fixture or explicit opt-in benchmark. This audit excluded it; it did not change package tests.

Completion means every matrix row has a passing, traceable regression, valid exceptions are preserved, all publication paths enforce the contract, app/package integration passes, and the Release performance gate remains satisfied. A plan alone does not establish that outcome.
