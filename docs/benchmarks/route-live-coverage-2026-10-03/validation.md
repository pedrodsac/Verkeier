# Route live coverage and caching validation — 3 October 2026

Final package revision: `65ca049952432e1da5771000b2347081b550adac`. App implementation revision: `7191e8a56cad1d0a1e661f3c139b232d0d35339c`. The project and resolved package lock both pin the final package commit.

All **161 package tests in 20 suites** pass with `ROUTING_VERIFY_KERNEL=1 swift test --disable-automatic-resolution --no-parallel`. All **78 simulator tests in 15 suites** pass on the pinned Release app with code coverage disabled. Serial package execution prevents the intentionally short matching-deadline fixtures from competing with the exhaustive dual-kernel oracle. Acceptance timing ran separately from builds, tests and CPU profiling.

Provenance: the complete eleven-scenario matrix ran **330 timed operations**, with 20 warm and ten cold operations per scenario, at package `237e9f5` / app `14d9620`. The final follow-up prioritizes already-cached boards before slow network work and skips this ordering for explicit refreshes. Its affected `paging` and `cached` paths were rerun for **60 additional timed operations** at package `65ca049` / app `7191e8a`. The table uses those final two distributions and retains the nine unchanged explicit-refresh distributions from the complete matrix. Each raw record and summary row identifies its run and exact revisions; the full eleven-scenario matrix was not rerun after this follow-up. There are 390 timed records and 13 discarded priming records in the raw artifact.

The Release gate passes: worst scenario/process p95 is **3.776 seconds** (deadline-arrive, cold). All 30 final timed compatible cached searches issue **zero departure-board requests and zero response bytes**; their cold p95 is **0.788 seconds**. The existing ten-scenario matrix is retained with a cached-search scenario added.

Environment: M4 MacBook Air, ten CPU cores, 16 GiB memory, iPhone 17 simulator, Xcode 27.0 (27A266a), Release, code coverage disabled, no debugger. Installed GTFS generation 4 contains 2,805 stops, 28,993 trips and 660,706 stop times, valid 30 September–12 December 2026. The installed pedestrian graph is reused. This feed differs from older performance reports, so these measurements establish the five-second gate rather than a controlled before/after speed ratio.

Timing runs through the production view model, service, planner, walking graph and visible route sheet. Recorded scenarios replace only ATP HTTP transport. Explicit calculations/refreshes bypass completed board evidence; paging uses caches and checks newly explored windows. `cached` primes compatible coverage and asserts zero network requests. Displayed-leg timing sources and matching rejection counts accompany acquisition, request, byte and cache counters. Logs announce small per-record file paths so large accumulated-page diagnostics cannot block the simulator console bridge.

| Scenario | Warm median / p95 (s) | Cold median / p95 (s) | Warm / cold board requests (median) | Warm / cold cache hits (median) |
|---|---:|---:|---:|---:|
| depart | 1.270 / 1.291 | 1.887 / 1.954 | 24 / 24 | 0 / 0 |
| reverse | 1.360 / 1.382 | 2.048 / 2.242 | 24 / 24 | 0 / 0 |
| coordinates | 1.238 / 1.257 | 2.010 / 2.575 | 24 / 24 | 0 / 0 |
| arrive | 1.488 / 1.602 | 2.256 / 2.858 | 24 / 24 | 0 / 0 |
| exact | 0.650 / 0.737 | 1.255 / 2.426 | 24 / 24 | 0 / 0 |
| rural | 0.583 / 0.590 | 1.169 / 1.184 | 24 / 24 | 0 / 0 |
| paging | 3.032 / 3.138 | 3.168 / 3.355 | 22.5 / 28 | 59.5 / 17 |
| refresh | 0.644 / 0.659 | 0.647 / 0.663 | 24 / 24 | 0 / 0 |
| recorded-live | 0.669 / 0.680 | 1.275 / 1.287 | 24 / 24 | 0 / 0 |
| deadline-arrive | 3.117 / 3.149 | 3.753 / 3.776 | 12 / 12 | 0 / 0 |
| cached | 0.684 / 0.742 | 0.699 / 0.788 | 0 / 0 | 24 / 24 |

Package fixtures cover later boarding occurrences without their own predictions, departures beyond the old 90-minute horizon, earlier/later pages introducing new trips, active-generation cancellations and delays, ranking changes, intermediate-stop updates, retained fresh observations, cross-consumer interval reuse, shifted windows, gap-only fetching, overlapping flights, independent cancellation, filter/language/credential/passlist isolation, original freshness, expiry and refresh races. The final regression verifies that covered boards behind four stalled network requests are matched before the acquisition budget expires. Existing tests continue to verify delayed-past catchability, transfer feasibility, cancellation, repeated stops, service dates and independent predicted arrivals/departures.

App fixtures compare on-time tracking, delays, downstream predictions and cancellation through stop-board mapping and route matching. They verify shared cached acquisition timestamps and zero additional board requests. An empty-board regression verifies that view-model freshness uses its original snapshot timestamp. Find Routes uses caches and explicit Refresh Routes bypasses them.

The recorded-live and cached fixture scenarios report one observed boarding out of five displayed legs (20%); all other boards deliberately return empty fixture responses. This is a controlled evidence check, not a measure of production live-data availability.

## Current stop-board comparisons

Live spot checks ran through the configured native app connection at the final revisions. The earlier direct-relay HTTP 403 did not prevent these native requests. Each query used its current launch time; after the initial forced calculation, the harness loaded displayed boarding-stop boards, recalculated the same fixed query using caches, and compared boards again. These three spot checks are outside the statistical Release gate.

| Query | Initial render (s) | Initial observed / displayed boardings | After board loading (s) | Cached-query observed / displayed boardings | Cache hits / new board requests |
|---|---:|---:|---:|---:|---:|
| Gromscheed → Kirchberg | 3.270 | 0 / 12 | 2.454 | 4 / 10 | 5 / 18 |
| Kirchberg → Gromscheed | 3.356 | 5 / 10 | 2.638 | 5 / 10 | 8 / 12 |
| Esch | 2.860 | 2 / 5 | 2.235 | 2 / 5 | 6 / 14 |

The first Gromscheed calculation received no completed boards within its acquisition budget and therefore published scheduled results; loading stop boards made four boardings available to the next calculation. Live coverage remains partial: unchecked, ambiguous or inconsistent observations remain scheduled under the two-second acquisition budget. The live data includes global `noCandidate` and `invalidTripTimeline` rejection counters; these do not attribute a specific missing leg to a specific rejection. Comparisons group by line and scheduled departure within 90 seconds and record multiple matches, so they are diagnostic evidence rather than a stronger identity match than the provider performs.

Loading only displayed boarding stops does not establish complete coverage for every reachable stop and interval in the route search. These live cached queries legitimately fetch uncovered frontier intervals; the zero-request requirement is verified separately by fully compatible cached fixture searches. Live response contents and query results can change between observations, so these samples do not prove universal live coverage or a controlled before/after coverage ratio.

Raw timing records are in [samples.jsonl](samples.jsonl), with selected distributions/stage/counter summaries in [summary.json](summary.json). Final live results are in [live-samples.jsonl](live-samples.jsonl), the same-query recalculations in [live-cached-comparisons.json](live-cached-comparisons.json), and per-stop observations in [live-board-comparisons.jsonl](live-board-comparisons.jsonl). No credentials or raw request URLs are included.
