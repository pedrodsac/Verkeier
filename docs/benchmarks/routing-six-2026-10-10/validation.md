# Six-route batch verification — 10 October 2026

MobiliteitKit `89d25e63c5a8e61770bdcb9082583882b2865fb6` returns up to six useful transit alternatives initially and per Earlier/Later operation. The app pins that revision. Walking and bike comparisons remain outside transit slots. Loaded journeys accumulate; normal invalidation, dominance and walking-refinement pruning remain active, so a published batch can contain fewer than six qualifying journeys.

Searches start at two hours, expand incomplete batches through 4/8/16/24-hour windows, and retain all round and pass records. Initial arrive-by searches also require the existing safe stopping proof. Later-arrival pages anchor their preceding 24-hour departure lookback to the original boundary while the future window expands; the combined span can reach 48 hours in a sparse case. This prevents a journey found in an early pass from disappearing during expansion. Live completion targets the same selected batch as publication, including nearest earlier journeys.

Transfer limits, dominance, walking evidence, cancellation/freshness checks, request concurrency and the eight-second live acquisition allowance are unchanged. Result counts and search-window scope intentionally change from the previous ten-route, three-hour facade. Explicit cursor counts and lower-level session defaults remain available.

## Validation

- Package Release suite: 238 tests passed with `ROUTING_VERIFY_KERNEL=1`, including generated-network/reference checks, six-route initial/adjacent accumulation, live targeting, sparse/partial windows, safe arrive-by stopping and stable later-arrival lookback.
- Integrated Release simulator build and 189 app tests passed. The build used the prior clean app source plus the new package pin, isolating unrelated working-tree feature edits.
- All final initial benchmark scenarios published six transit journeys. Pages requested six new candidates; ordinary accumulated-profile/refinement pruning still applies.
- 307 shared journey records and 508 transit-leg timing/source records matched between old and new runs. These checks cover exported times, legs, warnings and live sources for shared IDs; they do not assert identical result sets after the requested count/window change.
- Every recorded-live sample matched 21 predicted events. Every cached sample made zero board requests. No real ATP network latency claim is made by these recorded-response runs.

## Release simulator measurements

iPhone 17 / iOS 27, Xcode 27, installed October–December GTFS feed, October 8 anchors, measured walking graph, production dependency composition and recorded bike availability. The production route sheet rendered; the optional full map was not mounted. No debugger, CPU profiler or concurrent build was attached to the accepted benchmark runs.

Each scenario/build has exactly five operations: one priming operation, two warm samples and two fresh-process samples. The table excludes priming. Baseline samples were reused instead of rerun to respect the cap; these are small descriptive comparisons. Fresh-process runs retain installed datasets and OS filesystem caches. Paging and cached scenarios include untimed prerequisite calculations. Warm paging advances repeatedly, so the new six-route boundaries differ from the old ten-route boundaries.

Baseline package: `ca066cd0c666dd0fb7f9c085eba221234f62017f`. Values are median milliseconds through first rendered result; stages/refinements and completion evidence are retained in the raw records.

| Scenario | Old warm | Six warm | Old fresh process | Six fresh process |
|---|---:|---:|---:|---:|
| Departure | 622 | 509 | 1231 | 1160 |
| Rural | 384 | 698 | 957 | 1289 |
| Arrive by | 624 | 469 | 1228 | 1111 |
| Earlier arrivals | 341 | 516 | 639 | 540 |
| Later arrivals | 634 | 469 | 653 | 524 |
| Later departures | 411 | 500 | 242 | 515 |
| Earlier departures | 659 | 508 | 716 | 524 |
| Recorded live | 368 | 341 | 949 | 927 |
| Cached recorded live | 377 | 327 | 370 | 333 |

Departure, arrive-by and recorded-live initial searches improved in this series. Rural work increased because the old three-hour profile returned five routes, while the new search expands to four hours to return six. Some paging cases also increased: they fill six routes and visit different time boundaries. These results do not establish a universal speedup or physical-device latency guarantee.

A 90-minute prototype was rejected: it either stopped at an underfilled rural batch or, when corrected to fill six, required extra complete scans. With complete batches, its warm arrive-by median was 982 ms and rural median was 1,092 ms; the accepted two-hour policy measured 469 ms and 698 ms respectively.

## Every reported stage

Warm medians in milliseconds. Walking is nested in RAPTOR, board fetching/matching/decoding in realtime, and HTTP is aggregate concurrent work. Overlapping/nested stages must not be added together. The full files retain operation-relative spans, every horizon/realtime pass, rounds, transport measurements, candidates, coverage, memory high-water marks and route evidence.

| Stage | Old departure | Six departure | Old recorded live | Six recorded live |
|---|---:|---:|---:|---:|
| adapterMapping | 0.29 | 0.18 | 0.16 | 0.11 |
| bikeCalculation | 3.22 | 3.39 | 0.10 | 0.10 |
| boardFetch | 2.00 | 2.00 | 4.00 | 4.50 |
| boardMatching | 0.00 | 0.00 | 0.00 | 0.00 |
| candidateBuilding | 92.92 | 92.77 | 24.46 | 23.27 |
| decode | 0.00 | 0.00 | 0.00 | 0.00 |
| directWalkingWait | 0.00 | 0.00 | 0.00 | 0.00 |
| endpoints | 1.72 | 1.78 | 0.95 | 1.04 |
| firstRender | 55.22 | 50.11 | 41.31 | 53.72 |
| geometry | 0.87 | 0.54 | 0.49 | 0.35 |
| graphPreparation | 0.48 | 0.56 | 0.46 | 0.49 |
| http | 11.00 | 10.50 | 12.00 | 10.50 |
| publication | 1.02 | 1.04 | 1.00 | 1.01 |
| ranking | 0.08 | 0.05 | 0.05 | 0.03 |
| raptor | 421.06 | 308.10 | 252.13 | 215.50 |
| realtime | 36.82 | 36.11 | 44.72 | 44.21 |
| realtimeDiscovery | 23.63 | 24.83 | 38.55 | 38.30 |
| refinement | 3.52 | 3.68 | 0.13 | 1.09 |
| resultAssembly | 0.19 | 0.12 | 0.11 | 0.07 |
| schedulePreparation | 2.00 | 0.50 | 0.00 | 0.00 |
| snapshotPreparation | 0.12 | 0.13 | 0.11 | 0.12 |
| timetableReadiness | 0.42 | 0.39 | 0.37 | 0.39 |
| validation | 0.06 | 0.04 | 0.03 | 0.02 |
| walkingTransfers | 15.00 | 14.00 | 12.50 | 12.00 |

[Machine-readable comparisons and stage summaries](results.json) · [All 90 retained records, including priming](samples.json.gz) · [Test summaries](tests.txt)

## Reproduction

Use a Release simulator app built at the package revision above, with the same
installed GTFS snapshot (SHA-256 `fd855d3cf1b6fb775791b6f086948fd2ef6c50cb42fa424bddad5c0f6de80b9c`) and walking dataset. The GTFS archive
is not bundled. Recorded ATP and bike inputs are included beside this report.

```sh
python3 Scripts/benchmark_routes.py \
  --app /absolute/path/to/Release-iphonesimulator/Verkeier.app \
  --output /tmp/six-route-morning \
  --composition production --scenarios depart rural \
  --time 2026-10-08T08:00:00+02:00 \
  --fixture docs/benchmarks/routing-six-2026-10-10/recorded-live.json \
  --bike-fixture docs/benchmarks/routing-six-2026-10-10/bike-snapshot.json \
  --warm 2 --cold 2 --maximum-limit-ms 0
```

Other groups use the same flags: `arrive arrival-earlier arrival-later` at
09:00; `paging earlier` at 18:35; and `recorded-live cached` at 18:28. All anchors
are October 8 in `+02:00`. The zero gate selects measurement mode; it does not
shorten production acquisition or routing deadlines. Real-network runs remain
opt-in.
