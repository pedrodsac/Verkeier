# Range-McRAPTOR prototype vs the current kernel (14 November 2026)

**Verdict.** A textbook range multi-criteria RAPTOR, written as a benchmark-only prototype that reads the existing `RoutingSnapshot`, answers the same 2-hour
range queries **11× faster than the current kernel on 10 cores, and 35× faster than the current kernel on one core** (medians over 12 stop pairs, Mac).
Single-threaded, it takes **2–49 ms** per query on the Mac against **31–542 ms** for `Raptor.search` on 10 workers. Its result set is a **superset in the
Pareto sense**: every in-window journey the current kernel finds is either found too or beaten on departure, arrival, transfers and walking by one the
prototype finds. No prototype journey is beaten by a current-kernel journey. The prototype skips route- and trip-scoped transfer rules and block
continuations; on these 12 queries they change nothing, even in the current kernel. **Recommendation: replace `Raptor` with a range-McRAPTOR
kernel**, staged as described at the end. The open work is constrained transfers, the realtime overlay, slack-aware choice between equal journeys,
results beyond the 2-hour window, and arrive-by.

| | |
|---|---|
| Prototype | MobilitéitKit commit `fd28443` on local branch `proto/range-mcraptor` (not pushed), base `830726a`. Code in `Sources/MobilitéitKit/Routing/Prototype/`, harness in `Tests/MobilitéitKitTests/RangeMcRaptorBenchmarkTests.swift`. The only change outside those: `JourneyPlanningSession.endpointEdges` and its `EndpointEdgePurpose` lose `private`. `swift test --no-parallel`: 351 tests pass |
| App | MobilitéitKit pin untouched. No app code changed |
| Network | None. No ATP, relay or walking-service requests. Walking is a deterministic straight-line stand-in (below) |
| Raw results | `range-mcraptor-results.json` (Mac run: every Pareto tuple, comparison, statistic and timing), `run.txt` (console log with the legs of every differing journey), `width62-run.txt` (pairs 1, 3 and 8 with a wider current-kernel profile) |

## What was built

About 1,060 lines in seven files, each under 240 lines:

- **Timetable** (`RangeMcRaptorTimetable.swift`): flat `Int32` arrays built from the snapshot for service days D−1, D and D+1, so trips after midnight
  and the previous evening's late trips are boardable. Each GTFS pattern becomes one or more FIFO "routes", with trips sorted by departure and no
  overtaking, so the earliest catchable trip is a binary search. 1,747 patterns become 1,542 routes. 6 patterns are split, 205 have no trip on 22 October,
  and there are 16,889 trip instances. Boarding and alighting flags come from pickup and drop-off types. Build: **8.7 ms**.
- **Footpaths** (`RangeMcRaptorTransfers.swift`): one-hop edges, made of the GTFS pathway closure plus at most one walking transfer from
  `nearbyTransferStopsByStop`, matching `Raptor.relaxPathways` and `relaxWalkingTransfers`. The change time owed after each edge comes from stop-level
  transfer rules (`max(minimumTransferSeconds, rule.minimum)`; type 3 forbids the transfer), the same selection as `Raptor.selectedTransferRule`
  minus route and trip scope. There are 11,196 edges, plus a reverse index for the bounds. Build: **11 ms** once the walks are known.
- **Bounds** (`RangeMcRaptorBounds.swift`): a cheap reverse pass per query. It computes the minimum further rides per stop (a reverse round sweep
  over routes) and a time lower bound (Dijkstra over reversed per-hop minimum ride times and footpaths). Stops that cannot reach the destination
  are pruned. It takes **0.6 ms**.
- **Search** (`RangeMcRaptorSearch.swift`, `RangeMcRaptorWorkspace.swift`): rRAPTOR iterations from the latest departure to the earliest, keeping every
  bag between iterations. Each round scans only marked routes. A route bag holds (trip, walk) entries. The route alights before boarding at each stop,
  and boarding takes the earliest boardable trip at or after the label's ready time. Bags are per round and stop, up to 32 entries of `Int32`
  (arrival, ready, walk, label, walked). A label is dominated by any label in rounds 0…k at the stop that is no worse on all four. Destination
  pruning compares `arrival + time bound`, `rides + ride bound` and `walk + minimum egress` against the destination bag. The inner loop uses no
  `Date`, dictionary, closure or cancellation check.
- **Journeys** (`RangeMcRaptorJourneys.swift`): rebuilds every destination emission from parent links into access, transit, transfer and egress legs.
  It keeps the strict Pareto front over (departure, arrival, transfers, walking) with one journey per tuple.

Two variants were measured:

- **exact**: one iteration per distinct "boardable departure at an access stop − access walk" in the window. Departure is then an exact criterion
  (rRAPTOR as published). This is the variant to compare.
- **minute**: 120 iterations, one per minute. It is faster, but loses "leave later within the same minute" journeys (see the comparison).

Two criteria beyond the textbook were needed for correctness against this engine's semantics:

- **ready**: the arrival plus the change time still owed. Without it, a same-stop arrival that has not yet paid the change time would dominate a
  footpath arrival that has.
- **walked**: whether the label arrived by access or footpath. Footpath labels may not walk again (one footpath hop per round, as in the current
  kernel), so they must never dominate an arrival on board. This is OTP2's "arrived on board" criterion. Without it, the prototype lost real
  journeys: Gromscheed 20:10:16 → 20:50:22 went missing before this fix.

## Setup

- Installed feed **generation 5** (service 7 October – 12 December 2026), copied from the Mac app container. The service day is **Thursday 22 October
  2026**. The snapshot has 2,805 stops, 213 route- or trip-scoped transfer rules and 2,660 block continuations.
- Each pair queries a 2-hour window from the anchor time. Trips must start by the window end, the same cutoff (`profileUpperBound`) the current
  kernel applies. Up to 4 rides (`maxTransfers: 3`), `minimumTransferSeconds: 120`, buffer 0, all modes.
- Access and egress come from `JourneyPlanningSession.endpointEdges`: the origin stop plus up to 40 nearby stops, the same edges the app would pass.
  Walking uses a deterministic stand-in, `ceil(metres / 1.2)` s along a straight line, reported as routed, for access, egress and footpaths in
  both kernels. All 11,196 nearby pairs are accepted. Durations are therefore not the app's real walks, but both kernels see identical ones.
- The current kernel is `Raptor.search` with the same snapshot, access, egress and preferences, run after one warm-up with caches warm. It is timed on
  10 workers (`availableWorkers` on this Mac) and on 1 worker (`activeProcessorCountOverride = 1`). The prototype times include the bounds pass,
  workspace allocation, search and journey rebuild. They exclude the one-time timetable and footpath builds (8.7 ms and 11 ms).
- Published journeys: `TransitRouter` (no realtime provider, fixed clock) → `makeSession` → `initialSuggestions(count: 6, searchHorizon: 7200)`.
- Apple M4 MacBook Air (10 cores), on AC power, battery 100 %, Low Power Mode off. Build: `swift test -c release -Xswiftc -enable-testing --no-parallel`.
  Each pair ran 2 warm-ups and then 7 samples, alternating current (10 workers), current (1 worker), prototype minute and prototype exact.

## Timings

Median of 7 samples, milliseconds. Minimums are within 3 % of the medians in every cell (JSON).

| # | Pair (time) | Access / egress stops | Current, 10 workers | Current, 1 worker | **Prototype exact** | Prototype minute | Exact iterations |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | Gromscheed → Kirchberg Konrad Adenauer (18:11) | 25 / 25 | 288.0 | 928.3 | **8.3** | 6.7 | 339 |
| 2 | Esch Gare routière → Volmerange-les-Mines (18:35) | 25 / 11 | 204.0 | 618.7 | **12.5** | 6.3 | 577 |
| 3 | Hamilius → Kirchberg Luxexpo (08:00) | 25 / 25 | 508.8 | 1,863.2 | **48.8** | 11.9 | 1,496 |
| 4 | Gare Centrale routière → Cloche d'Or (12:30) | 25 / 25 | 542.2 | 1,981.3 | **31.9** | 7.7 | 1,149 |
| 5 | Clervaux → Remich Gare routière (07:30) | 18 / 18 | 86.4 | 232.9 | **6.5** | 5.4 | 280 |
| 6 | Wiltz Gare routière → Mondorf Casino (09:00) | 25 / 19 | 33.3 | 61.3 | **7.2** | 4.6 | 362 |
| 7 | Echternach Gare Centre → Belval Université (17:30) | 14 / 25 | 146.8 | 416.5 | **12.4** | 8.7 | 205 |
| 8 | Ettelbruck Gare routière → Esch Gare routière (16:00) | 25 / 25 | 229.3 | 705.1 | **28.0** | 17.7 | 529 |
| 9 | Differdange Arbed → Junglinster P+R (07:45) | 25 / 7 | 221.0 | 693.9 | **26.4** | 22.1 | 491 |
| 10 | Grevenmacher → Redange/Attert Gare (13:00) | 13 / 14 | 94.3 | 256.1 | **10.4** | 9.2 | 242 |
| 11 | Dudelange Gare → Diekirch Gare routière (22:00) | 25 / 25 | 31.4 | 55.6 | **4.4** | 4.7 | 131 |
| 12 | Troisvierges → Luxembourg Gare Centrale (06:30) | 10 / 25 | 208.3 | 661.5 | **2.3** | 2.3 | 143 |
| | **Median** | | **206.2** | **640.1** | **11.4** | **7.2** | |

Speed-up of prototype exact over the current kernel, across the 12 pairs: **4.6× to 92× on 10 workers** (median 11×, geometric mean 13×) and
**8.5× to 291× on 1 worker** (median 35×, geometric mean 38×). Minute iterations add a further 1.0–4.1×.

Where the time goes (prototype exact, from `exactStatistics`): pair 3 runs 1,496 iterations, scans 349k routes and creates 36k labels. Target pruning
rejects 2.2M of 2.4M label attempts. No bag ever overflowed its 32 entries; the largest held 14. Iterations dominate the cost, which is why the
city-centre pairs (3, 4), with many departures within walking reach, are the slowest. The 9 MB of bag storage per query (5 rounds × 2,805 stops ×
32 × 5 `Int32`) is allocated inside the timed call, and a production version should reuse it.

### iPhone 13

Same harness, feed and Release flags (`-O -enable-testing`, whole-module), on the owner's iPhone 13 (iOS 27.0.1, 6 cores) in **Low Power Mode**,
thermal state nominal throughout. Low Power Mode was already on and was left alone. It throttles the CPU, so all four columns are pessimistic;
expect both kernels to be faster with it off. Each pair ran 1 warm-up and 5 samples, alternating as on the Mac. Package tests cannot run on a
device, so the harness ran inside a throwaway host app. It was signed with an existing local development profile for an unused bundle id,
`dev.pedrocordeiro.LuxTransit`, and removed afterwards; the installed Verkeier app was not touched. The run ended during pair 11's diff output
(the phone most likely locked), and a rerun of pair 12 alone ended at launch, so **pair 12 has no iPhone timing**. For pairs 1–11 every Pareto set,
comparison and published-coverage result was identical to the Mac run (`iphone-run.txt`).

| # | Current, 6 workers | Current, 1 worker | **Prototype exact** | Prototype minute | Speed-up (6 workers vs exact) | iPhone / Mac (exact) |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 1,025.9 | 2,932.9 | **23.6** | 19.2 | 43.5× | 2.8× |
| 2 | 691.2 | 1,919.1 | **34.5** | 16.6 | 20.0× | 2.8× |
| 3 | 1,909.5 | 5,799.6 | **137.5** | 33.4 | 13.9× | 2.8× |
| 4 | 1,980.3 | 6,191.1 | **89.0** | 23.3 | 22.3× | 2.8× |
| 5 | 315.4 | 754.9 | **17.7** | 15.6 | 17.8× | 2.7× |
| 6 | 125.3 | 196.3 | **20.7** | 13.6 | 6.1× | 2.9× |
| 7 | 517.4 | 1,322.3 | **32.0** | 23.6 | 16.2× | 2.6× |
| 8 | 826.4 | 2,243.5 | **71.9** | 46.5 | 11.5× | 2.6× |
| 9 | 773.7 | 2,189.9 | **66.7** | 55.8 | 11.6× | 2.5× |
| 10 | 332.4 | 815.6 | **27.1** | 25.0 | 12.3× | 2.6× |
| 11 | 109.7 | 173.5 | **12.7** | 13.4 | 8.6× | 2.9× |
| **Median** | **691.2** | **1,919.1** | **32.0** | **23.3** | **13.9×** | **2.8×** |

On the phone the prototype answers in **13–138 ms** (median 32 ms) single-threaded. The current kernel needs **110–1,980 ms** (median 691 ms) on all six
cores. That is **6× to 44× faster** (median 14×), and 9.5× to 124× against the current kernel on one core. Gromscheed → Konrad Adenauer goes from
about 1 s to 24 ms. The phone is about 2.8× slower than the M4 for the prototype and 3.2–3.8× slower for the current kernel. Setup on the phone, done
once per feed: timetable 27 ms, footpath table 34 ms (snapshot load 0.8 s, which is shared with the current kernel).

## Result comparison

Per pair, Pareto sets over (departure, arrival, transfers, walking) restricted to departures in the window. "Beaten" means some journey of the other kernel
is no worse on all four criteria and better on one. The dominance check uses the other kernel's full set, including departures just after the window.

| # | Current | Prototype exact | Common | Current only (beaten by prototype) | Prototype only (beaten by current) | Constraints on vs off (current) | Published: equal / beaten / missing |
|---:|---:|---:|---:|---:|---:|---|---|
| 1 | 25 | 64 | 15 | 10 (10) | 49 (0) | identical | 4 / 2 / 0 |
| 2 | 8 | 8 | 8 | 0 | 0 | identical | 6 / 0 / 0 |
| 3 | 38 | 98 | 27 | 11 (11) | 71 (0) | identical | 6 / 0 / 0 |
| 4 | 15 | 30 | 15 | 0 | 15 (0) | identical | 6 / 0 / 0 |
| 5 | 6 | 10 | 6 | 0 | 4 (0) | identical | 6 / 0 / 0 |
| 6 | 3 | 5 | 3 | 0 | 2 (0) | identical | 3 / 0 / 3 |
| 7 | 19 | 42 | 19 | 0 | 23 (0) | identical | 4 / 2 / 0 |
| 8 | 14 | 29 | 10 | 4 (4) | 19 (0) | identical | 3 / 3 / 0 |
| 9 | 5 | 15 | 5 | 0 | 10 (0) | identical | 5 / 1 / 0 |
| 10 | 5 | 10 | 4 | 1 (1) | 6 (0) | identical | 4 / 2 / 0 |
| 11 | 12 | 12 | 11 | 1 (1) | 1 (0) | identical | 5 / 1 / 0 |
| 12 | 6 | 6 | 6 | 0 | 0 | identical | 5 / 0 / 1 |
| | **156** | **329** | **129** | **27 (27)** | **200 (0)** | **0 differences** | **57 / 11 / 4** |

**1. Every current-kernel journey is matched or beaten.** 129 of the 156 in-window current tuples appear in the prototype's set. The other 27 are
all beaten by a prototype journey. A clear case from pair 1, checked against `stop_time`: for the 18:21:35 departure (670 s walk to Mënsterbësch,
then the 361), the current kernel offers 18:56:15 and 18:56:21 with 1,222 and 1,138 s walking. Both get off at Héienhaff, walk to the P+R and take
the T1, then walk again. The prototype gets off one stop later at Parishaff and boards line 6 trip `19567` (18:41:00), which runs on through
Héienhaff (18:42:50) and Avalon (18:53:00) to Konrad Adenauer, the destination stop, at 18:54:20. That arrives earlier with 670 s walking.

*Is it the label quota?* Only partly. Pairs 1, 3 and 8 were rerun with `Raptor.profileWidth` raised from 48 to 62, the most its `UInt64` slot masks
allow (`width62-run.txt`). Beaten current tuples fell from 25 to 21, prototype-only tuples from 139 to 126, and the current kernel got 26–29 %
slower. With the wider profile, the current kernel does find trip 19567. But it boards at Héienhaff and gets off at Avalon to walk 273 s (18:57:33,
943 s walking), instead of riding one more stop to the destination stop (18:54:20). So part of the gap is the bounded profile, and part is another
pruning rule in the current kernel that was not traced here. That is worth a look as a current-kernel defect whatever is decided, because it reaches
published pages (point 4).

**2. The prototype finds about twice as many Pareto journeys** (329 vs 156), and none of them is beaten by a current journey. Most extras are
genuine trade-offs: leaving later for a little more walking, one more transfer for an earlier arrival, or an alternative access stop. The current
kernel cannot keep them all because each stop keeps a bounded label profile. The app shows 6 per batch after `JourneyQualityPolicy`, so a larger
input set means more choice for the page, not more on screen.

**3. Constrained transfers make no difference on these queries.** The current kernel was run on the full snapshot and on a copy with route- and
trip-scoped rules and continuations removed (`stripConstraints`). All 12 Pareto sets were identical (156 of 156 tuples). The prototype's omission of
the 213 scoped rules and 2,660 block continuations therefore caused **0 result differences** here. Omitting them can only *lose* journeys, never
produce invalid ones. All 213 scoped rules are route-scoped and relax a transfer: 211 are timed (type 1, no minimum) and 2 require 60 s (type 2,
routes 423 ↔ 424 at Wecker-Gare). Under `transferDecision` they resolve to the 120 s default. Where they outrank a stricter stop-level rule, the
current kernel allows 120 s for that route pair while the prototype requires the stop's rule. 48 of the 49 stops concerned also have a stop-level
rule above 120 s, mostly 300 s (Echternach Gare Centre, Ettelbruck, Esch Gare routière, Grevenmacher, Mersch, Redange and others). Missing
continuations likewise turn a stay-seated ride into a transfer with change time. See open issues.

**4. Published journeys.** Of the 72 journeys the session would publish (6 per pair), 57 are in the prototype's set and 11 are beaten by a prototype
journey. Some of those 11 are beaten only by seconds of walking (pairs 1, 7 and 10: 6–13 s). Others are clearly worse options on today's page:

- Pair 1: 18:37:25 → 19:09:30 (326, then the 25 to Bricher Gässel and 590 s on foot). The prototype has the same departure arriving 19:05:12 with
  62 s walking (326, then the 21 to prov. Konrad Adenauer), and other tuples that arrive up to 10 minutes earlier.
- Pair 8: 16:26:02 → 18:05:05 with 2 transfers. The prototype leaves 18 minutes later with 1 transfer and the same arrival.
- Pair 9: 08:28:06 → 10:21:27 with 285 s walking. The prototype leaves 26.5 minutes later with no walking and the same arrival.
- Pair 10: 13:10:00 → 14:53:15 with 3 transfers. The prototype leaves 9.6 minutes later with 2 transfers.

The 4 missing ones all lie outside a 2-hour range query by construction, because the session widens its horizon when the window gives it too few:

- Pair 6 (Wiltz → Mondorf): 09:18:05 → 11:41:30 rides the 501 from Howald at 11:17:30. That trip starts after the 11:00 cutoff; without the cutoff the
  prototype finds the same tuple. 10:15:53 → 14:06:00 rides the 550 from Bettembourg at 13:45. Without the cutoff the prototype beats it.
  11:28:00 → 14:48:30 departs after the window.
- Pair 12 (Troisvierges → Gare Centrale): the 09:05 RE departs 35 minutes after the window (06:30–08:30). Without the cutoff the prototype finds it.

**5. Minute vs exact iterations.** Minute iterations lose 33 of the 329 tuples (pair 7 alone loses 13 of 42) and gain none that survive. The lost ones
leave later within the same minute, and in a minute iteration nothing prefers the later departure. Exact iterations cost 1.0–4.1× more but stay under
50 ms on the Mac.

**6. Cutoff.** Without the trip-start cutoff the prototype finds 143 further tuples; 25 cutoff tuples are then beaten by journeys on later trips. The
current kernel uses the same cutoff, so the comparison above is like for like.

## Open issues

### Constrained transfers (213 scoped rules, 2,660 block continuations)

Measured cost of skipping them: 0 differences in 12 pairs. The structural cost: timed route-pair connections at 48 stops, and stay-seated rides,
can be lost, but no invalid journey can appear (point 3 above). Handling them in a range-McRAPTOR, following OTP2's constrained transfers:

- **Scoped rules** (`from_route`/`to_route`/`from_trip`/`to_trip`). Precompute a bit per (route, stop position) saying "a scoped rule may apply when
  boarding or alighting here". Unflagged positions keep today's fast path. Each transit label already records its trip, so at a flagged boarding the
  scan looks up the rule for (arriving trip or route → this trip or route). Type 3 skips that label for this route only. Type 1 (timed) and type 2
  (minimum time) replace the stop-level `ready` with `arrival + rule time`, which may allow a connection the stop default forbids. Dominance must not
  discard such a label: at flagged stops, the label's trip-specific class becomes an extra bag criterion, as `walked` is now. The bags stay small
  because only a few hundred (stop, route) pairs are flagged.
- **Block continuations** (stay-seated). When a route scan reaches the last stop of a trip with a successor in the same block, the route-bag entry
  continues on the successor trip's route from its first stop in the same round. Rides are not incremented and no change time applies. In practice
  this is a second scan pass per round over the (successor route, trip, label) pairs collected in the first, repeated while chains continue. It adds
  cost only where continuations exist.
- Both need the equivalence harness extended with queries where the current kernel's results do depend on them. None of these 12 do, so pick them from
  the snapshot (stops with scoped rules, through-running lines).

### Realtime overlay

v1 has none. Proposal: one search keeps publishing once, live. After the boards arrive, patch a per-search copy-on-write overlay of the affected trip
rows: delayed departures and arrivals, and flags cleared for cancelled stops or trips. Then run one range query. Patching costs time proportional to
the affected trips, a few hundred at most, so well under a millisecond. Delays can break FIFO order inside a route (a late bus behind an on-time one). A
patched route must then be checked, and either fall back to a linear trip scan or move the late trip to an overflow route for that search. Because
the timetable covers D−1…D+1, a delayed earlier trip is still on the scan. Added or replaced trips (not in GTFS) and the exact overlay semantics
the current kernel applies need checking against `TransitRouter`'s realtime path; that check is a TODO. **The kernel is not where the live search
latency is.** The earlier re-baseline found the client at about 0.4–0.8 s outside realtime, with the relay and ATP wait dominating. A 10–50 ms
kernel removes most of the client part, not the network part.

### Slack ranking

The current kernel uses minimum and total transfer slack as dominance criteria in its profiles (`RaptorCompactProfile`, `cannotEnterFullProfile`), so it
prefers safer transfers between otherwise equal journeys. `JourneyAssessment` later checks feasibility with live times. The prototype has no slack
criterion: among journeys with equal (departure, arrival, transfers, walk) it keeps the first one found, deterministically but without regard to safety.
Options:

- (a) A tie-breaker on exact equality in the bags. It is cheap, but slack is a whole-journey property and bags see prefixes, so it is only approximate.
- (b) **Recommended:** a transfer-optimisation pass after the search, like OTP2's. For each result journey, it re-chooses the transfer stops and
  connecting trips that keep the same departure, arrival, rides and walk while maximising minimum slack, then total slack. It costs nothing in the
  search and acts only on the few journeys that survive.

Making slack a full Pareto criterion would grow bags and iterations for little benefit.

### Also needed before it can replace `Raptor`

- **Real walks.** The benchmark used straight-line walks. The app already has the stored transfer-walk table (11,188 pairs, built once per walking
  graph and timetable), which is the natural source for the footpath edges. Building the prototype's edge table from known walks takes 11 ms.
  Access and egress stay with `endpointEdges`.
- **Beyond the window.** The session publishes journeys on trips after the 2-hour cutoff when the window yields too few (pairs 6 and 12). The range
  query needs the same behaviour: a second range query over the next window, or a longer first window. Cost grows roughly with the number of
  iterations; the uncut runs cost about the same as cut ones.
- **Arrive-by.** This needs the mirrored search (latest arrival, iterating arrival times). It was not prototyped.
- **Preferences.** `allowedModes` and pathway preferences are respected, as are minimum transfer and buffer. `allowTightSameStopBusTransfers` is not
  implemented.
- **Exact vs minute.** Use exact iterations, or minute iterations plus an exact pass only at the origin stop if iteration counts grow on a bigger feed.
- **Equivalence at scale.** Before switching, run hundreds of pairs over several days, with and without realtime replays. The gate: every current
  journey is equal or beaten, and published pages are reviewed for quality.

## Recommendation

Replace `Raptor.search` with a range-McRAPTOR kernel. The evidence: one core does in about 10 ms what the current kernel does on ten cores in about 200 ms, and it returns a Pareto
superset. Suggested order:

1. Productionise the kernel in MobilitéitKit behind a flag. Use exact iterations, a reused workspace, footpaths from the stored transfer-walk
   table, preferences, and the slack post-pass.
2. Add constrained transfers and block continuations, with targeted equivalence queries.
3. Add the realtime overlay patching and the horizon widening that `JourneyPlanningSession` relies on.
4. Run the equivalence harness at scale, then switch the session to the new kernel and delete the profile kernel and its worker pool.

This makes the routing pass close to free on the phone. Near-instant live search then depends on the relay and ATP wait, which needs its own work.

## Reproduce

In a worktree of MobilitéitKit on `proto/range-mcraptor`:

```sh
ROUTING_BENCHMARK_DATABASE=<generation-5 feed .sqlite> RANGE_MCRAPTOR_BENCHMARK=1 RANGE_MCRAPTOR_OUTPUT=<dir> \
  swift test -c release -Xswiftc -enable-testing --no-parallel --filter RangeMcRaptorBenchmarkTests
```

Optional: `RANGE_MCRAPTOR_SAMPLES` (default 7), `RANGE_MCRAPTOR_WARMUPS` (2), and `RANGE_MCRAPTOR_PAIRS` (for example `1,3,8`). The feed is not in
the repository: generation 5 was copied from the Mac app container (`Library/Application Support/…/gen5.sqlite`).
