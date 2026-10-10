# Routing equivalence and performance — 10 October 2026

The selected capped series reduces warm departure latency by 7.5%, later paging
by 13.6%, and captured live replay by 3–9%. Fresh-process results are mixed,
including a 7.5% Esch replay regression. Common route fields match in all fourteen
selected controlled cases and all four captured-live cases; complete native
journeys and completed walking plans also match in their separate quality checks.
This is not acceptance of a universal latency or no-regression guarantee: final
physical-device timing remains unavailable and sample counts are deliberately small.

The implementation preserves the existing search horizons, three-transfer limit,
48-label profile capacity, dominance and quota rules, deterministic chunk merge
order, live coverage requests, passlists, freshness rules and eight-second live
acquisition allowance. Faster processing comes from reusing immutable work and
reducing allocation; elapsed deadlines can still produce different evidence on a
real network. There is no universal five-second latency guarantee.

## Changes

MobiliteitKit builds service-day anchors, stop-occurrence lookups and reverse
walking adjacency with the immutable snapshot. A bounded session cache reuses
trip-instance arrays when the effective timing overlay is identical; each pass
still checks its query window and pickup eligibility. Realtime timeline and
passlist matching use occurrence-aware indexes and memoized pure alignment.
Completed boards warm timestamp/name conversions while the remaining network
requests proceed; matching and patch merging retain their original order.

The compact kernel skips quota work below capacity, mutates one destination
profile throughout serial merging and recycles worker scan buffers. Sparse
profiles grow storage while retaining the original slot numbers, width and
allocation-independent comparison rules. Candidate transit legs and immutable
journey status evidence are calculated once; publication still reevaluates
freshness, cancellation and feasibility.

The app caches dataset metadata using file identity, size and modification time.
Directed measured paths are shared across transit, bike-share and refinement,
with graph revision keys and coalesced in-flight work. A path uses the same
validated immutable dataset for its cache key and engine, avoiding a second
metadata lookup and a graph-update race between those steps. Independent bike paths
use a bounded task group; results are considered in the original station-pair
order, with the same availability preference and warnings.

## Measurements and reproduction

Routing diagnostics retain every search pass and round, operation-relative spans,
validation/ranking and bike/refinement/rendering work. HTTP and decoding totals
are cumulative concurrent work, not elapsed latency. Opt-in URLSession metrics
report connection reuse, pre-fetch delay, connection time, response wait, transfer
time and encoded bytes. Pre-fetch delay is not an isolated measurement of the
transport's internal connection queue.

The benchmark can use the production dependency composition and the actual
TransitMapLayer behind the route sheet. `mapRender` measures a committed display
frame, not completion of remote basemap tile downloads. It does not measure all
other map-screen interactions. ATP runs are explicit `live-*` scenarios, stop on
HTTP 429/provider errors or a request budget, and capture only successful bodies;
provider error bodies and access credentials are excluded. Captured board queries
can be replayed exactly; an uncaptured query aborts instead of fabricating evidence.
Bike snapshots can also be saved and replayed.

```sh
python3 Scripts/benchmark_routes.py --app /absolute/path/Verkeier.app \
  --output /absolute/path/results --composition transit \
  --scenarios depart reverse coordinates rural --warm 2 --cold 2 \
  --time 2026-10-08T08:00:00+02:00 --maximum-limit-ms 0

python3 Scripts/compare_route_benchmarks.py /absolute/path/baseline \
  /absolute/path/optimized --output /absolute/path/comparison.json
```

Use `--fixture` with recorded board dates matching the selected installed feed and
planning time. Use `--composition production --full-map` for the app composition;
add `--bike-fixture` for repeatable availability. Live capture uses
`--request-budget`; `--compare-boards` opts into additional departure-board checks.
`--capture-directory` replays successful captured board queries offline.
Each case is capped at five operations, including priming. The default is one
priming operation, two warm samples and two fresh-process samples. Earlier runs
completed before this limit are retained separately; they are not repeated.
`--full-evidence` exports complete plans for quality comparisons; leave it off
for memory measurements to avoid carrying prior JSON serialization high-water
marks into subsequent warm samples.

`Scripts/benchmark_routes_device.py` runs an explicitly compiled
`ROUTING_BENCHMARK` Release build on a connected iPhone. It copies the same feed
and fixtures into temporary files, preserving the device's installed timetable.
Benchmark code remains excluded from ordinary physical-device builds.

## Validation scope

The package suite runs with `ROUTING_VERIFY_KERNEL=1`, comparing compact and
reference labels, IDs, paths, quotas and ordering. It covers generated networks,
repeated stops, overtaking, continuations, frequencies, DST/midnight, cancellations,
sparse/delayed/stale forecasts, partial boards, paging, force refresh and cancelled
walking work. New regressions compare whole published journeys between fresh and
reused sessions, preserve first exact/legacy occurrence lookup, invalidate walking
paths by direction and graph revision, and redact diagnostic credentials.

Two previously failing tests were corrected without changing router policy: the
matching-deadline test uses a deterministic matching checkpoint, and the tiny
network oracle includes tight-transfer risk.

The preserved original app has an older benchmark schema. Paired comparisons
explicitly list the route fields available in both schemas and fields that could
not be compared. The new harness can additionally export complete unfiltered plans
and paging flags for future comparisons. Passing sampled comparisons and kernel
verification is evidence for equivalence, not an exhaustive proof over all feeds.

The final package revision is `ca066cd0c666dd0fb7f9c085eba221234f62017f`.
The Release app integration is `7a80d6d`, following `8660f95` for shared walking
and bounded bike paths, `15a59a6` for reuse of the validated walking dataset,
and `bbb3c84` for optional full-evidence exports. The original package is
`91ad7171201b0c0bb21e5f94e04ecceb38fdb6b6`; the preserved app baseline was built
from `b91fc4e`. The installed feed contains 2,805 stops, 28,017 trips and 641,818
stop times, valid 7 October–12 December 2026 (generation 5). Controlled queries
use 8 October anchors and the same 21 September Valhalla 0.6.3 walking graph.

The final package suite passes **232 tests in 34 suites**, with compact/reference
verification enabled. The Release simulator app passes **189 tests in 33 suites**;
a signed physical-device Release build also succeeds. Installed full-feed
compact/reference verification passes separately from timing runs.

A second replay compiles the original package source and the final package
against identical immutable inputs: the same installed feed, fixed clock,
coordinates, walking evidence and typed realtime patches. Departure, reverse
arrive-by and exact Esch scenarios each exercise initial, later, earlier, delayed,
cancelled and reset operations. **All 126 complete journeys across 18 operations
are equal**, including every exported native journey field and full leg values,
IDs, order, recommendations, realtime state and paging flags. The canonical JSON
SHA-256 is `cee3f0235e4fc48fbc715fb4db85ec3ab471893e99d133d6517ef51b20e465bd`.
This complements recorded ATP matching fixtures; it does not assert identical
results across changing real-network observations.

### Completed walking evidence

The earlier long arrive-by paging series exposed a measurement race: the harness
sampled after the first rendered result while walking refinement continued.
Across 23 operations, 49 field comparisons differed. Journey ID sets were equal;
two operations differed in ordering, and other differences involved fractional
walking timestamps or a walking span before versus after merging. Those
intermediate snapshots are **not** a passing exact-equivalence result and remain
in [intermediate-paging-comparison.json](intermediate-paging-comparison.json).

The harness now waits for actual refinement-stream completion before exporting
evidence, while retaining the previously recorded first-render latency. Completion
is counted per request generation, including recursively scheduled corrections;
superseded requests cannot delay the current generation. Production publication
and refinement behavior are unchanged. Tests cover stream completion and
superseded work.

Three targeted cases compare complete plans after refinement: normal earlier
arrive-by paging, earlier paging around 7 October at 15:00, and later paging
around 8 October at 23:00. Each uses two operations per implementation. All
available fields, **including full Codable plans, walking geometry, timings,
recommendations, IDs and ordering**, match exactly. These are quality checks,
not additional performance claims. See
[settled-walking-comparison.json](settled-walking-comparison.json).

## Captured live results

Successful ATP responses from the real-network run were replayed through the
same decoding and matching code at their exact planning timestamps. The original
app received only the harness additions needed to replay those queries; its
router and package remain at the original revisions. All available route fields
match, including IDs, ordering, recommendations, leg times, evidence, coverage,
matching rejections and paging. Native complete-journey replay above covers
fields absent from the original app harness.

| Scenario | Warm before → after | Fresh process before → after |
|---|---:|---:|
| Live departure replay | 1,677 → 1,533 ms (−8.6%) | Not paired |
| Live reverse replay | 1,364 → 1,323 ms (−3.1%) | 2,113 → 2,039 ms (−3.5%) |
| Live Esch replay | 569 → 531 ms (−6.6%) | 1,155 → 1,241 ms (+7.5%) |
| Cached live Esch replay | 444 → 452 ms (+1.8%) | 465 → 464 ms (−0.1%) |

Departure uses one priming operation and four warm samples per implementation;
the other cases use one priming operation, two warm samples and two fresh
processes. Five existing baseline departure samples were recovered from a run
started before the cap; no additional baseline departure calculations were made.
The Esch fresh-process regression is retained in the report, not hidden by the
warm improvement. Two fresh samples are insufficient to establish a stable
tail-latency distribution. Cached replay issued zero board requests.

## Real network findings

These are individual completed production-composition operations with the map
layer, not controlled before/after comparisons. Network observations change.

| Scenario | First rendered result | Board fetching | Matched predicted events | Decoded bytes |
|---|---:|---:|---:|---:|
| Departure now | 6,468 ms | 4,113 ms | 3,248 | 15.24 MB |
| Reverse now | 5,006 ms | 2,941 ms | 2,439 | 13.23 MB |
| Esch now | 3,833 ms | 2,671 ms | 2,387 | 11.53 MB |

Observed departure coverage was 94%, 63% and 60%, respectively. Of 108 subsequent
departure-board leg comparisons, 49 had a unique row and an observed forecast;
all 49 agreed. Other comparisons lacked those conditions and are not treated
as successful forecast equivalence checks.

Cached recalculations took 1,540 / 1,350 / 481 ms respectively, each with zero
board requests. Connections were reused for these HTTP measurements. Median
pre-fetch delays were below 3 ms, while median response waits were approximately
0.9–1.3 seconds. Server/proxy response wait remains the main live bottleneck.

The live arrive-by initial result rendered in 14,405 ms: live acquisition used
7,984 ms and RAPTOR used 5,192 ms. The benchmark's 200-request safety budget was
exhausted during subsequent, untimed board-comparison requests. Its initial
result is preserved separately; it is excluded from the fully completed live
validation set. No HTTP 429 was needed to stop the run.

A counterbalanced concurrency experiment used three operations at 16 requests
and three at 24, retaining the same request coverage. Median totals were
5,622 and 5,482 ms, but the difference did not hold consistently across adjacent
runs and network variation exceeded two seconds. Production remains at 16;
`--live-concurrency` is an explicit benchmark-only override.

## Physical device status

A signed Release build succeeds for the iPhone 13. An earlier optimization
revision completed recorded-device runs, but the phone became unavailable to
Xcode before final-revision verification could finish. Those earlier timings
are not presented as final-device performance. Final latency and memory on a
physical phone remain unverified.

## Saved evidence

[results.json](results.json) retains stage/counter/memory summaries and real
transport measurements. [samples.json.gz](samples.json.gz) retains the selected
sample records, including spans and rounds. The comparison files state which
fields were available in both harnesses. Full native journey evidence is in
[native-journeys.json.gz](native-journeys.json.gz), with its digest in
[native-equivalence.json](native-equivalence.json).
[provenance.json](provenance.json) records source revisions, executable/feed/graph
hashes, build inputs, test counts and selection rules.
[baseline-harness.patch](baseline-harness.patch) contains only the original-app
benchmark additions for captured queries, fixed timestamps/preferences, completion tracking and complete-plan
exports. Raw logs and successful live bodies remain under
`/tmp/verkeier-routing-implementation-2026-10-10`.

The selected five-operation comparison covers fourteen controlled scenarios.
For morning, arrival, exact-stop and later-paging cases, it reuses the first
priming, first two warm and first two fresh samples already collected before
the user imposed the cap. Those series were not rerun. Remaining series enforce
the cap in both simulator and device drivers. Warm memory in the earlier harness
can include high-water marks from prior full-plan JSON exports; fresh-process
memory is collected before its first export. Full-plan quality runs are kept
separate from memory claims.

## Controlled five-operation comparison

Each median uses two samples. Paging, refresh and cached cases include untimed
prerequisite setup, so a fresh process does not imply empty caches. These timings
measure first rendering; complete walking-evidence comparisons are separate.

| Scenario | Warm before → after | Fresh process before → after |
|---|---:|---:|
| arrival-earlier | 387 → 379 ms (-2.0%) | 688 → 673 ms (-2.2%) |
| arrival-later | 740 → 693 ms (-6.2%) | 688 → 718 ms (+4.2%) |
| arrive | 688 → 625 ms (-9.2%) | 1,262 → 1,262 ms (-0.0%) |
| cached | 391 → 381 ms (-2.5%) | 402 → 407 ms (+1.2%) |
| coordinates | 702 → 637 ms (-9.2%) | 1,288 → 1,282 ms (-0.5%) |
| deadline-arrive | 8,647 → 8,551 ms (-1.1%) | 9,191 → 9,162 ms (-0.3%) |
| depart | 689 → 638 ms (-7.5%) | 1,330 → 1,235 ms (-7.1%) |
| earlier | 739 → 677 ms (-8.5%) | 750 → 731 ms (-2.6%) |
| exact | 386 → 393 ms (+2.0%) | 1,057 → 982 ms (-7.2%) |
| paging | 485 → 419 ms (-13.6%) | 314 → 256 ms (-18.7%) |
| recorded-live | 398 → 393 ms (-1.2%) | 973 → 971 ms (-0.1%) |
| refresh | 374 → 368 ms (-1.7%) | 398 → 397 ms (-0.4%) |
| reverse | 735 → 727 ms (-1.0%) | 1,430 → 1,373 ms (-4.0%) |
| rural | 427 → 390 ms (-8.6%) | 996 → 961 ms (-3.5%) |

## Every reported stage

Optimized timings in milliseconds: controlled departure uses two warm samples;
real live departure is one fresh production-composition operation. Scalar totals
sum recorded intervals; concurrent refinement branches and nested stages can
overlap. HTTP and decoding report cumulative request work. Do not add the rows
to estimate latency. Spans retain the underlying operation-relative intervals.
These earlier timing exports may precede completion of walking refinement; the
current harness and settled quality exports wait for completion.

| Stage | Controlled departure | Real live departure |
|---|---:|---:|
| adapterMapping | 0.29 | 0.31 |
| bikeCalculation | 13.65 | 418.46 |
| boardFetch | 2.50 | 4113.00 |
| boardMatching | 0.00 | 96.00 |
| candidateBuilding | 95.01 | 265.66 |
| decode | 0.00 | 114.00 |
| directWalkingWait | 0.00 | 0.00 |
| endpoints | 1.70 | 198.27 |
| firstRender | 58.39 | 168.45 |
| geometry | 0.91 | 3.47 |
| graphPreparation | 1.55 | 87.42 |
| http | 13.50 | 37656.00 |
| mapRender | — | 168.42 |
| publication | 1.08 | 5.10 |
| ranking | 0.08 | 0.09 |
| raptor | 423.51 | 1147.06 |
| realtime | 42.68 | 4259.33 |
| realtimeDiscovery | 29.14 | 29.11 |
| refinement | 12.66 | 13.04 |
| resultAssembly | 0.19 | 0.26 |
| schedulePreparation | 1.50 | 16.00 |
| snapshotPreparation | 0.24 | 319.23 |
| timetableReadiness | 1.17 | 1.80 |
| validation | 0.06 | 0.12 |
| walkingTransfers | 15.50 | 201.00 |

The production bike/map case used one priming, two warm and two fresh operations,
with captured bike availability and the measured walking graph. All five
produced the same vel’OH! station-pair alternative. Warm rendering took
859 ms and fresh rendering 1,701 ms; the concurrent bike
branch took 14.9 / 141.5 ms. Its committed map frame took
49.2 / 99.0 ms. The bike tie/order regression test separately
forces out-of-order path completion and compares the whole selected option.
