# Gromscheed → Kirchberg, Konrad Adenauer: simulator benchmark

The five-run median fell from **4,702.567 ms to 2,313.462 ms**, a **50.804% improvement**. The predeclared 50% target was ≤2,351.284 ms.

## Fixed measurement setup

- Same iPhone 17 simulator, UDID `F726825E-2DB4-4F45-A51C-DBA5AA0E2664`, iOS 27.0.
- Release, code coverage off, no debugger, full map and production service/view-model composition.
- Five fresh app processes per build. The runner labels the first sample priming and the next four cold; the metric includes **all five** in both builds.
- Departure fixed at 2026-10-11 11:47:12.890348 Europe/Luxembourg (epoch `1791712032.890348`).
- Gromscheed `49.6541071,6.2296443` → Kirchberg, Konrad Adenauer `49.62995,6.158028`, stop `000200417019`.
- Same GTFS generation 5 and OSM graph, 7,200-second horizon and four rounds per pass.
- Strict offline replay of the single earlier live iPhone run: 29 captured HTTP 200 boards, 6,643,468 bytes and 1,651 predicted events, plus its recorded bike snapshot. Missing replay queries fail. These are simulator replay timings; the physical iPhone 13 was not remeasured.
- Baseline app commit `0b09d9d`, MobiliteitKit `ac6945e96e84cc3614317024cae716b0f90aca5c`; optimized package `562bca26973968113cc6c5d9d69228142c8819d5`.

## Timing breakdown

Stage medians in milliseconds. Stages can overlap or nest, so do not sum this table.

| Part | Baseline | Optimized |
| --- | ---: | ---: |
| Snapshot preparation | 302.705 | 294.379 |
| Graph preparation | 51.685 | 42.776 |
| Endpoint walks | 133.006 | 87.969 |
| RAPTOR including walking transfers | 3709.613 | 1381.735 |
| Walking transfers (subset of RAPTOR) | 2462.000 | 1005.000 |
| Candidate building | 219.391 | 219.827 |
| Realtime | 193.841 | 188.315 |
| First render | 93.088 | 90.692 |
| Bike calculation (overlapping work) | 108.957 | 77.549 |

| Fresh process | Baseline total ms | Optimized total ms |
| --- | ---: | ---: |
| 1 | 5221.918 | 2402.387 |
| 2 | 4652.292 | 2313.462 |
| 3 | 4627.801 | 2297.164 |
| 4 | 4838.751 | 2302.427 |
| 5 | 4702.567 | 2327.592 |

Four of five optimized runs individually meet the half-baseline-median target; the declared median meets it.

## Changes

- Keep compact RAPTOR scans for mixed-depth linked vehicle services, comparing the complete trip key without allocation. This removes the expensive reference-kernel fallback while preserving its ordering.
- Share batch walking futures rather than creating one forwarding task per route; preserve coalescing, correction and cancellation behavior.
- Resolve the active walking graph once per batch and bound native walking work across four serialized engine actors.
- For short walking batches, try correlation without the default 50-node reachability probe. The actual pedestrian search must succeed within 1,500 metres and 900 calibrated seconds; otherwise retry normal correlation. Individual long walks and funicular terminal walks retain normal correlation.
- Explicitly request no turn instructions (`._none`, fixing an accidental Optional.none), decode measured timing/distance/path only, reuse actor-confined JSON coders and omit redundant waypoint defaults.
- Configure the public native null logger once in Release to avoid per-route stdout locking/flushing. Debug logging and application errors remain available.

Grouped multi-leg requests and a custom native correlation cache were measured and discarded. No vendored Boost headers or experimental native routing implementation are included.

## Route and workload checks

All five optimized samples have exactly the same six canonical transit plans and supplemental plan as the baseline, including precise timing, geometry and realtime state. All four previously displayed journeys and their leg evidence remain present. The final filtered display contains six journeys rather than four; its selected option also differs, so this is not a claim of identical UI selection/filtering state. The raw evidence records both states.

All counters and the logical counts in all eight rounds are identical: 3,600 candidates, 1,249 duplicates suppressed, 64 invalid journeys, 21 retained alternatives, 9 delayed past boardings and 10 workers. Walking workload stays at 13,600 requests, 9,877 cache hits and 3,723 actual calculations. No horizon, round, realtime coverage or walking-workload reduction explains the gain.

Maximum sampled simulator peak memory rises from 858,701,824 to 948,043,776 bytes (about 89 MB / 10.4%), principally a tradeoff of the larger native engine pool. This needs separate physical-device validation before treating simulator memory or latency as iPhone measurements.

## Validation

- MobiliteitKit: **259 tests in 44 suites passed**, with `ROUTING_VERIFY_KERNEL=1 swift test`, including compact/reference equivalence and shared-batch cancellation/coalescing tests.
- App: **218 tests in 39 suites passed** in Release on the same simulator with code coverage off. Native walking fixtures compare original and minimal requests, including geometry/timing equality for correlation reachability 0 and 50; batching/fallback/cancellation are covered.
- Builds and tests were finished before the final timed runs; no parallel build or profiler ran during measurement.

`baseline.json` and `optimized.json` retain all five measurements and one copy of each full canonical plan set, with per-sample SHA-256 checks. `comparison.json` contains the calculated metric, medians and verified invariants.

## Reproduce locally

The following uses the original local capture and immutable optimized app snapshot. `Baseline.app` is the original build, and `Coders.app` is the final optimized build in the same temporary directory. The network payloads and binaries are local artifacts, not checked into Git.

```sh
python3 Scripts/benchmark_routes.py \
  --device F726825E-2DB4-4F45-A51C-DBA5AA0E2664 \
  --app /tmp/verkeier-konrad-simulator-50/Coders.app \
  --output /tmp/verkeier-konrad-simulator-50/reproduction \
  --scenarios live-depart --warm 0 --cold 4 --epoch 1791712032.890348 \
  --capture-directory /tmp/verkeier-iphone13-konrad-2026-10-11/network \
  --bike-fixture /tmp/verkeier-iphone13-konrad-2026-10-11/bike-snapshot.json \
  --destination-name 'Kirchberg, Konrad Adenauer' \
  --destination-coordinate 49.62995 6.158028 --destination-stop 000200417019 \
  --full-map --full-evidence --request-budget 0 --maximum-limit-ms 0
```
