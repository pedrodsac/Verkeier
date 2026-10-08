# Initial live transfer calculation — 8 October 2026

The initial calculation discovers alternative outgoing lines and applies their
observations to RAPTOR feasibility before publishing routes. It does not depend
on `refreshDisplayedRealtime` to discover the regression's connection.

Current MobiliteitKit revision: `353a15755b9c98c5e8f23c80aa1124c35bf010f3`.
Earlier measurements below retain their original revisions.

## Regression and policy

The scheduled first vehicle reaches the interchange at 08:10; line 202 leaves
at 08:08. A slower line 203 provides a scheduled fallback. Live observations
move the first arrival to 08:11 and line 202's departure to 08:14, making line 202
catchable and preferable. The ATP mock honors line filters: fetching line 203
does not supply line 202's observations.

Before the change, both departure and arrive-by cases failed because the first
result omitted the connection. The final `LiveTransferDiscoveryTests` checks
ten cases: both time modes with an ordinary fallback, a fallback-only request
that stalls, no scheduled route, an exhausted positive CPU allowance, and
1.4-second live responses. The rescued connection is present and recommended
in the first page with live timing on both legs.

Selected itinerary targets and destination-aware optimistic discovery targets
are merged into one concurrent batch. Selected stops retain queue priority.
Nearby boardings reuse a requested vehicle's passlist; long rides retain
additional boarding checks before forecast propagation expires. Initial CPU
work cannot consume the live-acquisition opportunity. Newly selected vehicles also use the remaining shared acquisition budget;
CPU elapsed time cannot suppress their live checks. Explicit schedule-only
requests and zero acquisition allowances remain supported.

The app selects an eight-second acquisition allowance with sixteen concurrent
requests. A direct live board request on 8 October took 7.397 seconds. The former
2.5-second cutoff could therefore cancel forecasts that were available from
the source. Slow replies may take the initial calculation beyond the historical
five-second rendered target.

Matching is limited to the selected and optimistically reachable vehicles, while
ambiguity is resolved against the full timetable before eligibility filtering.
This retains newly catchable alternatives without constructing patches for
unrelated vehicles returned on the same board.

## Verification

```sh
ROUTING_VERIFY_KERNEL=1 swift test --disable-automatic-resolution --no-parallel
```

All **194 tests in 26 suites passed** at the current revision. Existing coverage includes cancellation,
missed transfers, delayed-past boarding, full-timetable ambiguity, cache reuse,
paging, stale observations, long trips with incomplete earlier passlists,
and selected boarding priority over stalled discovery branches. Priority is
asserted at the provider request queue, independently of concurrent URLSession
start order.

The app regression uses a scheduled 08:25 incoming arrival and an 08:20 line-20
departure. Live times move those to 08:26 and 08:32. It checks the first service
return for a recommended, fully observed connection in both time modes and
both cache and forced acquisition modes, before any displayed-route refresh.
The Release simulator build passed all **19 focused app tests in four suites**:
`LiveTransferCalculationTests`, `JourneyPlanningIntegrationTests`,
`RouteContinuationTests` and `RouteRealtimeTrackingTests`.

## Native source diagnostic

A macOS Debug diagnostic queried Senningerberg Gromscheed → Kirchberg Konrad
against the installed feed and production relay. With a 2.5-second allowance,
all twelve board attempts expired before useful responses arrived. With a
10-second diagnostic allowance, the batch completed in 5.187 seconds, covered
thirteen boards, and the **initial result** contained nine reported departures
and nine reported arrivals across nineteen transit legs. No displayed-route
refresh was called. This diagnostic used a larger allowance than the app and
is not a simulator rendering measurement.

Other legs retained scheduled evidence. The diagnostic does not establish that
the source provides an unambiguous forecast for every future vehicle; unmatched
or unavailable observations must not be presented as live.

## Rendered source check before matching optimization

At revision `3ab7c7a`, the Release iPhone 17 simulator harness completed a
priming calculation and one warm live calculation, with no debugger or coverage.
Both initial results had nine observed departures and arrivals among ten
displayed transit legs. The remaining line-322 trip had one matching departure
board entry and no realtime departure forecast. An immediate cache comparison
retained those sources with zero network requests, establishing that a later
tracking pass was not responsible for the initial evidence.

Rendered times were **9,501 ms** for priming and **6,723 ms** for the warm query.
The warm query spent 2,629 ms matching the large board responses. These exceed
the old five-second gate. The final package additionally filters matching to
selected and discovered eligible vehicles; these timings precede that change.
Raw samples, comparisons and logs are in `source-check-3ab7c7a/`.

## Baseline rendered verification before conversion memoization

The earlier `601bc09` Release build passed the same 19 focused app tests. Its live
priming and warm calculations completed with **nine observed departures and
arrivals across twelve displayed transit legs** in each initial result. All
24 requested boards were covered. Rendered times were **10,457 ms** for priming
and **8,062 ms** warm. The warm matching stage took 3,925 ms: the eligibility
filter did not establish a performance improvement in this changing live dataset.
These are two source checks, not a latency distribution or a passing five-second
gate. Raw evidence is in `final-601bc09/`.

## Matching optimization and newly selected vehicles

The large matcher cost came from repeating pure conversions across vehicle
passlists: DateFormatter parsing, normalized stop/line names and local-noon GTFS
service-day anchors. `738de00` adds bounded per-batch memoization and avoids
normalizing a stop name after its external identity already matches. It does
not cache matching decisions or remove competing timetable candidates.

`353a157` also corrects a separate initial-result gap. A three-vehicle path
becomes selected after the first live overlay, but its third board was absent
from discovery. Previously an exhausted positive CPU allowance suppressed the
second acquisition entirely. The regression failed four assertions before the
change and passes with a live third departure/arrival in the initial return.
That check uses the remaining eight-second shared acquisition allowance.
The app omits the legacy CPU allowance so adjacent live pages cannot turn into
schedule-only searches when that elapsed-work subtraction reaches zero.

A recorded seven-stop board set and the same installed feed were replayed with
Release macOS executables at `601bc09` and the optimized revision. Both emitted
**293 trip patches containing 8,012 events with identical matched
timing, source and status fields**. Their normalized output
files are byte-identical, SHA-256
`cb679cbb19b9a7d5a116af8efa73f54eaf467d2c31b62d3c02a47a67d07df3da`.
The first isolated replay reduced matching from **2,926 ms to 173 ms**, and total
provider time from 3,169 ms to 448 ms. This is a matcher experiment, not app
rendering or a latency distribution. The recorded set also matches the previously
scheduled line-32 trip `24367162` to its available 09:25 forecast at stop
`000200409005`; its GTFS departure is 09:25:40.

`Scripts/profile_live_board_matching.swift` provides explicit capture and replay
modes. Compile it against a Release MobiliteitKit build; capture requires an
installed GTFS database and the user's configured proxy URL. Replay intercepts
all requests with recorded JSON and cannot contact ATP. Raw public boards and
the installed feed remain local rather than bundled into the app or tests.

```sh
# From the MobiliteitKit checkout, after swift build -c release:
swiftc -O -parse-as-library -I .build/release -I Sources/CSQLite \
  -L .build/release -lMobiliteitKit -lsqlite3 -lz \
  /path/to/Verkeier/Scripts/profile_live_board_matching.swift \
  -o /tmp/profile-live-boards
/tmp/profile-live-boards capture /path/to/timetable.sqlite \
  /tmp/recorded-boards /tmp/baseline.json "$API_PROXY_URL"
/tmp/profile-live-boards replay /path/to/timetable.sqlite \
  /tmp/recorded-boards /tmp/optimized.json
```

## Rendered verification after optimization

The pinned `353a157` Release build passed all **19 focused app tests in four
suites**. With code coverage disabled and no debugger, the native route-sheet
harness completed six live operations: one priming and one warm operation in
each of three scenarios. Raw samples, board comparisons and logs are in
`optimized-353a157/`. These are changing-clock spot checks, not a p95 series.

| Scenario | Priming ms | Warm ms | Warm matching ms | Warm board fetching ms |
|---|---:|---:|---:|---:|
| Depart now | 7,043 | 4,847 | 123 | 2,407 |
| Reverse now | 8,126 | 6,085 | 239 | 2,715 |
| Arrive one hour ahead | 11,202 | 11,457 | 70 | 3,048 |

All **28 unambiguous available departure forecasts** in the departure/reverse
initial board comparisons were applied before publication: 12 across the two
departure operations and 16 across the two reverse operations. Each departure
result displayed eight observed departures among twelve transit legs; remaining
legs had no realtime departure forecast in the comparator. Both selected line-32
vehicles were observed on the first return. Other displayed forecasts that the
comparator could not uniquely select were also observed; they are excluded from
that 28-forecast count. Arrive-by comparisons found no unique forecasts for its
displayed historical boardings, so that run establishes timing, not live coverage.

The departure warm query is back below five seconds, while priming, reverse and
arrive-by still exceed it. Arrive-by spent 7.4–7.7 seconds in the complete routing
scans. Its 24-hour profile and final scans remain intact, and the live allowance
was not shortened to obtain faster timings. This run used the harness's explicit
zero timing limit to characterize those failures; it is **not** a passing universal
five-second acceptance gate. The deterministic replay in `matching-replay.json`
separately establishes the matching speedup without changing input boards.
