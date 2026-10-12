# Live search halving — work in progress

The goal remains **incomplete**. Every journey must halve its original total live-search latency through rendered results. Offline replay latency does not satisfy this goal. Stop further live work if ATP reports a quota limit, as requested by the user. ATP returned HTTP 429 during the candidate32 Beiler run; work stopped. The user subsequently lifted the quota and work resumed.

| Journey | Original live total | Required total |
| --- | ---: | ---: |
| gromscheed-konrad | 7.337 s | 3.669 s |
| sandweiler-lorentzweiler | 5.221 s | 2.611 s |
| beiler-rumelange | 8.574 s | 4.287 s |

## Experimental live measurements

| Build / experiment | Journey | Total | ATP requests |
| --- | --- | ---: | ---: |
| overlap-live | beiler-rumelange | 6.997 s | 71 |
| overlap-live | gromscheed-konrad | 4.514 s | 27 |
| overlap-live | sandweiler-lorentzweiler | 4.128 s | 27 |
| partitions16-live | beiler-rumelange | 6.934 s | 60 |
| partitions16-live | gromscheed-konrad | 6.514 s | 29 |
| partitions16-live | sandweiler-lorentzweiler | 4.805 s | 30 |
| partitions32-audit | gromscheed-konrad | 5.153 s | 29 |
| lookahead16-live | beiler-rumelange | 5.939 s | 67 |
| candidate32-live | gromscheed-konrad | 4.984 s | 28 |
| candidate32-live | sandweiler-lorentzweiler | 3.956 s | 30 |
| scoped-refresh32-live | gromscheed-konrad | 5.559 s | 26 |
| scoped-refresh32-live | sandweiler-lorentzweiler | 5.264 s | 30 |
| scoped-refresh32-live | beiler-rumelange | 8.644 s | 56 |
| horizon-pilot32-live | beiler-rumelange | 5.535 s | 32 |
| concurrent-completion32-live | gromscheed-konrad | 4.523 s | 31 |
| concurrent-completion32-live | sandweiler-lorentzweiler | 3.002 s | 31 |
| concurrent-completion32-live | beiler-rumelange | 5.055 s | 54 |
| flight-sharing32-live | gromscheed-konrad | 4.743 s | 30 |
| flight-sharing32-live | sandweiler-lorentzweiler | 3.229 s | 31 |
| early-vehicles32-live | gromscheed-konrad | 5.542 s | 31 |
| early-vehicles32-live | sandweiler-lorentzweiler | 5.445 s | 30 |
| early-vehicles32-live | beiler-rumelange | 6.087 s | 43 |
| temporal-reuse32-live | gromscheed-konrad | 4.030 s | 30 |
| temporal-reuse32-live | sandweiler-lorentzweiler | 5.238 s | 30 |
| temporal-reuse32-live | beiler-rumelange | 5.544 s | 42 |
| adaptive-partitions32-live | gromscheed-konrad | 5.134 s | 33 |
| adaptive-partitions32-live | sandweiler-lorentzweiler | 2.891 s | 31 |
| shared-scheduling32-live | gromscheed-konrad | 5.439 s | 35 |
| shared-scheduling32-live | sandweiler-lorentzweiler | 3.387 s | 35 |

These are individual Release simulator samples at the original fixed planning timestamp, 2026-10-12 18:16:07 Europe/Luxembourg. HTTP acquisition times and realtime content vary between runs, so the rows do not establish causal percentage improvements. Successful rows above captured HTTP 200. The flight-sharing32, adaptive-partitions32 and shared-scheduling32 Beiler runs aborted on HTTP 503 (not 429) and have no accepted totals. The aborted candidate32 Beiler run captured HTTP 429 and has no accepted total. None proves the complete goal. The 32-concurrency audit reconstructs the service and pre-opens the walking graph; it is exploratory and cannot be used as final production-composition acceptance evidence.

## Changes and verification

- Walking caches retain directed measured paths with bounded LRU eviction. Graph and timetable preparation overlap in the app.
- Full schedule-only walking preparation and selected vehicle checks overlap initial live-board acquisition. Preliminary journeys are never published; acquired realtime controls the authoritative search. Cancellation and missed-connection fixtures preserve correctness.
- Forced calculations reuse only complete evidence acquired after their refresh boundary. Compatible line partitions and overlapping time intervals share fresh cached or pending work; only gaps require HTTP. Unknown line metadata forces acquisition of the original scope.
- Long-distance horizon preparation chooses a starting horizon using the timetable, then live cancellation can force further expansion. Session transport requests use the original windows, without the extra four-hour padding from earlier experiments.
- Shared Hafas scheduling caps overlapping requests across discovery and selected vehicle checks. Generic providers retain the four-slot reservation. Cancellation retains the final request's permit until its fetch task exits.
- Line shards have been removed in the latest candidate. Each stop now retains its full selected-line union in one work unit, reducing HTTP requests without narrowing time windows or truncating passlists. Tests verify lines beyond the former eight-line boundary and partial evidence after a later window times out.
- Walking-label insertion rejects exact dominated projections before allocation. Snapshot grouping avoids repeated string construction and temporary arrays while preserving ordering.

The latest package suite passed 289 tests in 57 suites with `ROUTING_VERIFY_KERNEL=1`; live-download and installed-feed tests were excluded. The Release app build passed. The full app suite passed 235 tests in 42 suites against the preceding package revision. Logs and exact revisions are recorded in `progress.json`.

## Authoritative local state

`progress.json` retains measurements, targets and raw artifact paths. Experimental app binaries, captures, full plans and logs are under `/tmp/verkeier-live-halving`. Package routing changes are committed and pushed through `00536fd`, including temporal reuse, the full preliminary vehicle pass, snapshot allocation reduction, shared acquisition scheduling, and complete per-stop board acquisition. The app pins that exact revision and the Release build passed. Its live run is pending. The preceding shared-scheduling run captured HTTP200 for Gromscheed and Sandweiler; Beiler aborted on HTTP503, with no quota response. The latest completed app suite passed 235 tests in 42 suites against the preceding `cef6074` pin.

The shared scheduler lets initial discovery use available capacity while preserving a single provider-wide concurrency cap across overlapping connection checks. Queued cancellation starts no HTTP, active cancellation retains its permit through fetch teardown, and expired work retains incomplete evidence. Generic providers retain the 28+4 reservation. No accepted live sample yet proves all three half-time targets.

## Further review

Raw captures show that response wait dominates the slowest HTTP calls and does not correlate reliably with board size. Adding frequency-weighted or time shards has no demonstrated payoff. Distinct requested stops do not share explicit returned boarding-platform identities, and the installed GTFS has no parent-station metadata, so cross-stop consolidation is unsupported.

The original 30-minute outward transport rounding remains: its extra rows can contribute live patches within global matching bounds. Reusing the preliminary full RAPTOR result also requires exact overlay equivalence, stable walking corrections/graph revision and no failed walking lookups; the current live captures contain real predicted changes. Neither optimization was weakened to force a faster measurement.

The walking binary creates a deep-stack pthread for every native route. A persistent worker could reduce local preparation cost, but requires rebuilding the upstream XCFramework. Router snapshot persistence or staged endpoint preparation is a broader change; real app startup already prepares the router. These findings do not establish completion of the three live latency targets.
