# Route calculation performance

The five-second simulator target is implemented. The routing-failure prevention delivery also passes the full 300-operation Release gate: worst scenario/process p95 4.787 seconds, including the acquisition deadline. See [1 October validation](benchmarks/routing-prevention-2026-10-01/validation.md) for the newer evidence. Measurements and raw per-request evidence are in [`benchmarks/route-performance-2026-09-30/`](benchmarks/route-performance-2026-09-30/). This report distinguishes the Release acceptance run from the separate Debug audit.

## Acceptance boundary

The clock starts in the production `TransitMapViewModel` calculation or paging operation and stops after the production `RouteView` has committed the complete initial result and idle loading state. A window-attached `CADisplayLink` observes two display callbacks after publication. It includes timetable readiness, remaining graph/snapshot preparation, endpoint walking, the realtime attempt, local routing, mapping, publication and the rendered sheet. It excludes dataset downloads, unresolved location and later decorative geometry refinement. A routing timeout, empty result, stale diagnostic identifier or still-loading sheet fails the harness.

Search coverage remains three hours for initial departure searches, 24 hours for arrive-by/paging, three transfers, and 48 labels per profile. Walking validation, preferences, useful alternative selection and recommendation policy are retained. Realtime acquisition can expire independently; acquired evidence survives and incomplete coverage is reported honestly while the full scheduled search continues.

## Implementation

- Correlated `RoutingDiagnostics` use `ContinuousClock` and fresh operation identifiers. Results carry preparation, endpoint, realtime acquisition, HTTP/decode, schedule preparation, matching/discovery, RAPTOR/round, walking, assembly, geometry, adapter, publication and rendering timings plus request/cache/coverage counters. Historical snapshot metrics remain separate. The former “RAPTOR CPU” number is identified as non-walking elapsed time.
- RAPTOR scan candidates and profiles store compact scalar keys and lightweight indices. Fractional timestamps are retained. Incoming-trip bitmasks, cached eviction bounds and indexed boarding arrival ranks reject impossible candidates before allocation. Eligible alighting positions are computed once per trip/remaining-round constraint. Chunk merging retains the original deterministic order and identifiers; predecessor/leg objects are materialized only for surviving labels. Worker concurrency is bounded and expensive chunks start first.
- Realtime boards use complete stable UTC 30-minute slices, assemble cached coverage and fetch gaps. Saturated intervals split rather than becoming false coverage. Both cache layers retain original acquisition timestamps under the existing 60-second freshness rule; refresh bypasses both layers. One absolute deadline spans fetching, decoding, schedules, matching, event creation and discovery. `RealtimeConfiguration.acquisitionBudgetMilliseconds` defaults to 4,000, including decoding older configuration; Verkéier selects 2,000.
- The route stream publishes the entire calculated snapshot immediately. Five staggered reveals and their roughly 400 ms artificial delay are removed. Startup preparation and the local walking-router pool remain. A conservative geodesic bound rejects impossible direct-walking comparisons before Valhalla, while actual paths still undergo the existing length validation.

## Measurement setup

Measured on an M4 MacBook Air (10 CPU cores, 16 GB RAM), iPhone 17 / iOS 27 simulator, Xcode 27, Release app process. The installed Luxembourg GTFS snapshot has 2,807 stops, 29,469 trips and 671,107 stop times, valid 24 September–12 December 2026. The installed walking graph is the 21 September 2026 dataset with Valhalla 0.6.3. The app pins MobiliteitKit revision `5649aeb2f611968821699d8c18da6a521d8f37c3`.

The final matrix covers ten scenarios and 300 timed operations. Each scenario has 20 warm samples after a discarded priming operation and 10 fresh app processes. Cold means a new process with installed datasets; OS filesystem caches may be warm. Paging and refresh prime a prerequisite page before their timed operation, including in a fresh process. The benchmark intentionally defers normal startup snapshot preparation to charge the first request for it. It uses the real view model, adapter, walking graph and visible production route sheet in a simulator-only harness; the main map screen is not mounted behind that sheet. Ordinary app navigation retains startup preparation.

No debugger, code coverage or concurrent CPU profiling was attached. Recorded scenarios substitute only ATP HTTP transport using the checked-in delayed-passlist fixture; other boards return explicit empty fixture responses. `recorded-live` asserts that predictions were actually matched. `live-*` scenarios use the configured production proxy. Repeated Calculate/Refresh operations deliberately bypass caches, so their HTTP counts do not demonstrate reuse; shifted-window/gap reuse is tested separately.

Peak memory is `getrusage(RUSAGE_SELF).ru_maxrss`, a process high-water mark, including startup graph work and cumulative warm-session allocations. It is not memory attributable to a single operation. This harness creates its own graph service alongside normal app initialization, so its memory readings include that additional startup work.

## Release results

`depart` is Gromscheed coordinates → Kirchberg Konrad stop at 08:00; `reverse` swaps endpoints; `coordinates` uses coordinates at both ends; `arrive` uses a 09:00 deadline; `rural` targets Clervaux coordinates. `exact`, `paging` and `refresh` use exact stops Esch (`000220402034`) → destination (`000400000095`) at 18:35. `recorded-live` uses 18:28 so the 20-minute lookback includes the planned 18:09 / predicted 18:38 Bus 651 departure. `deadline-arrive` uses the same arrive-by query with a silent HTTP fixture, forcing the entire realtime budget to expire before the complete scheduled search. Fixed queries are dated 30 September 2026. `live-now` uses the current clock; `live-arrive` uses the fixed 09:00 deadline with actual network transport.

| Scenario | Warm median / p95 / max | Cold median / p95 / max | Peak MiB (warm / cold) |
|---|---:|---:|---:|
| depart | 0.909 / 0.927 / 0.948 | 1.426 / 1.436 / 1.436 | 651 / 648 |
| reverse | 1.080 / 1.091 / 1.098 | 1.643 / 1.663 / 1.663 | 659 / 652 |
| coordinates | 0.910 / 0.922 / 0.927 | 1.425 / 1.577 / 1.577 | 646 / 643 |
| arrive | 2.380 / 2.439 / 2.441 | 2.900 / 2.946 / 2.946 | 934 / 906 |
| exact | 0.555 / 0.565 / 0.569 | 1.030 / 1.044 / 1.044 | 548 / 545 |
| rural | 0.519 / 0.527 / 0.529 | 0.990 / 0.996 / 0.996 | 568 / 566 |
| paging | 2.024 / 2.162 / 2.228 | 2.253 / 2.354 / 2.354 | 837 / 752 |
| refresh | 0.560 / 0.567 / 0.570 | 0.555 / 0.567 / 0.567 | 547 / 547 |
| recorded-live | 0.598 / 0.615 / 0.632 | 1.078 / 1.090 / 1.090 | 550 / 549 |
| deadline-arrive | 4.276 / 4.351 / 4.372 | 4.813 / 4.842 / 4.842 | 936 / 893 |

Times are seconds. p95 uses the nearest-rank definition; with ten cold samples it equals the maximum. All timed operations completed with a rendered result and loading finished. Full stage timings, round counters, request counts, option identifiers and memory measurements are retained in `samples.jsonl`; per-scenario medians are in `summary.json`. A [visible-sheet capture](benchmarks/route-performance-2026-09-30/visible-route-sheet.png) and [validation provenance](benchmarks/route-performance-2026-09-30/validation.md) accompany the data.

The original measured arrive-by baseline was 9.24–9.74 seconds before rendering; the final recorded-data cold p95 is 2.95 seconds through rendering. Baseline comparisons are limited samples rather than a controlled same-run statistical comparison.

### Earlier live-network measurements

A separate 20 warm / ten cold series per scenario used actual network transport at package revision `5aaebf5`. These 60 measurements predate the final scalar/profile/mask optimizations and are retained separately in `live-network-prior-*.json*`; they are not mixed into the final pinned matrix.

| Scenario | Warm median / p95 / max | Cold median / p95 / max | Peak MiB (warm / cold) |
|---|---:|---:|---:|
| live-now | 1.074 / 1.261 / 1.402 | 1.755 / 2.145 / 2.145 | 446 / 445 |
| live-arrive | 3.574 / 3.690 / 3.798 | 4.160 / 4.325 / 4.325 | 956 / 905 |

### Critical stages and realtime availability

| Cold scenario | Snapshot | Endpoints | Realtime | RAPTOR (incl. walking) | Candidate building | Render after publication | HTTP requests |
|---|---:|---:|---:|---:|---:|---:|---:|
| depart | 0.232 | 0.101 | 0.121 | 0.618 | 0.246 | 0.064 | 72 |
| arrive | 0.233 | 0.101 | 0.125 | 2.149 | 0.193 | 0.058 | 72 |
| recorded-live | 0.232 | 0.097 | 0.186 | 0.446 | 0.036 | 0.040 | 96 |
| deadline-arrive | 0.233 | 0.101 | 2.086 | 2.085 | 0.194 | 0.059 | 4 |

The silent HTTP fixture starts cancellation at the absolute two-second acquisition deadline; draining cancelled URLSession children adds about 86 ms at the median. This cleanup is included in the rendered gate. The full-budget case was 5.12–5.34 seconds before the final kernel refinements and is now below five seconds across all 30 timed samples.

Stages overlap: walking is included in RAPTOR; realtime includes acquisition, schedule preparation, matching and discovery. HTTP/decode sum completed response work across concurrent requests and do not sum to request wall time. A zero HTTP/decode value with zero response bytes indicates no successful response, not zero network waiting; `boardFetch` still measures that waiting. Medians of individual stages need not add up to the median total.

The earlier 20/10 live-network series encountered unavailable boards (zero covered boards and prediction events at the median); those routes explicitly used scheduled data. Earlier live “now” spot checks acquired 53–90 predicted events and delayed-past boardings, expired around the two-second deadline with honest partial coverage, and rendered in approximately 2.1–2.7 seconds. Arrive-by spot checks rendered in approximately 4.2–4.6 seconds, with no matched predictions for their fixed historical query window. Their raw samples are retained separately. The recorded-live 20/10 series provides reproducible matched-prediction coverage, including the delayed Esch departure. The observed simulator p95 passes the target; these samples do not establish future network availability or physical-device performance.

## Debug audit

Debug was built with coverage disabled and run without a debugger. This is a small audit: one warm and one cold timed operation per scenario, plus one discarded priming operation; it is not a p95 acceptance series. All four timed operations rendered complete results, but Debug does **not** meet the five-second target.

| Scenario | Warm seconds | Cold seconds | Peak MiB (warm / cold) |
|---|---:|---:|---:|
| depart | 22.635 | 24.362 | 650 / 650 |
| arrive | 46.807 | 49.102 | 932 / 874 |

The unoptimized Swift build spends most of this time in the RAPTOR scan/profile loops. The Release gate must be checked with `-configuration Release`; the default Debug simulator build is unsuitable for judging routing latency. Debug timings and stages are saved in `debug-summary.json` and `debug-samples.jsonl`.

## Correctness and validation

The reference RAPTOR scanner remains available behind `ROUTING_REFERENCE_KERNEL=1`. `ROUTING_VERIFY_KERNEL=1` executes differential checks for scan profiles, deterministic merging and pathway pruning, including identifiers, fractional times, departure times, trip keys, walking totals and predecessor legs. The installed full-feed comparison passed after compact merging and direct profile materialization. The final peer-mask reuse also passed the reference-enabled offline suite. A deterministic 4,000-insertion profile test compares the complete retained profile against the original implementation after every insertion.

The final package suite passed **96 tests in nine suites** with kernel verification enabled. The pinned app suite passed **41 tests in nine suites** with coverage disabled. Existing offline cases cover transfer rules, overtaking, repeated stops, cancellation, delayed-past departures, preferences, midnight/DST and directed walking. Added cases cover shifted “now” reuse, missing interval gaps, saturated boards, forced refresh, freshness propagation, already-expired deadlines, expiry during matching with retained evidence, operation correlation and immediate whole-snapshot publication. Existing app cancellation/stale-request tests remain passing.

Package milestones: `237edfe` diagnostics/compact kernel, `d237bc1` cache/deadline, `9e94d77` materialization after merging, `bb2491f` matching-expiry coverage, `5aaebf5` freshness/pathway follow-through, `367bc06` scalar alighting/profile indexes and `5649aeb` peer-mask reuse. App milestones: `5e8715c` pinned integration/publication/render tracing, `dac358c` opt-in simulator harness and `53858b6` full-budget gate/final pin.

## Reproduce

Install the current GTFS and walking dataset through the ordinary app first. No archive or production feed URL is embedded in the benchmark. Ordinary tests do not opt into installed-data or network benchmarks.

```sh
xcodebuild -project Verkeier.xcodeproj -scheme Verkeier \
  -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17' \
  ENABLE_CODE_COVERAGE=NO build

python3 Scripts/benchmark_routes.py \
  --app /absolute/DerivedData/Build/Products/Release-iphonesimulator/Verkeier.app \
  --output /tmp/verkeier-route-benchmark \
  --scenarios depart reverse coordinates arrive exact rural paging refresh recorded-live deadline-arrive

# Optional: uses the configured production proxy and current installed schedules.
python3 Scripts/benchmark_routes.py \
  --app /absolute/DerivedData/Build/Products/Release-iphonesimulator/Verkeier.app \
  --output /tmp/verkeier-route-live --scenarios live-now live-arrive

xcodebuild -project Verkeier.xcodeproj -scheme Verkeier \
  -destination 'platform=iOS Simulator,name=iPhone 17' -enableCodeCoverage NO test
```

The script defaults to 20 warm and ten cold samples; `--warm`, `--cold` and `--device` allow an explicit audit configuration. It writes logs, `samples.json` and `summary.json`. A simulator launch without `--routing-benchmark` opens the normal app. Debug is measured by building with `-configuration Debug` and passing the Debug app path. Use `--p95-limit-ms 0` for the separate Debug audit. By default the script exits with an error if any measured scenario/process p95 exceeds 5,000 ms. Debug measurements do not satisfy the Release gate.

In the MobiliteitKit checkout, `ROUTING_VERIFY_KERNEL=1 swift test` runs the offline differential suite. The opt-in `InstalledTimetableBenchmarkTests` accepts `ROUTING_BENCHMARK_DATABASE=/absolute/installed/timetable.sqlite`; it never downloads feeds or contacts ATP. Full-feed reference verification should run separately from timing samples because it deliberately computes both kernels.
