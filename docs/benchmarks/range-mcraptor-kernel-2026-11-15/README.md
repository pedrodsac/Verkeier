# Range-McRAPTOR kernel: equivalence at scale and the default switch (15 November 2026)

**Verdict.** The range kernel is ready to replace the profile kernel, and it is now the default on a local MobilitéitKit branch. On
**1,800 random queries** (3 seeds × 300, each with and without synthetic realtime), every journey the profile kernel can publish is matched or
beaten by one the range kernel can publish: **missing = 0**. The range kernel finds about **twice as many** Pareto journeys. Within a session, a search
takes a median of **11.6 ms** against **31.4 ms** for the profile kernel on 10 workers, with p90 84 against
209 ms. Getting there took four fixes, all found by this harness: two kernel bugs, one kernel/normaliser mismatch, and one window-edge
difference. Open issues:
- queries limited to one transfer are slower (median 10.8 against 4.2 ms);
- the realtime overlay copies the whole timetable (about 8–9 ms);
- rail-preference queries still have tails of 600–770 ms, as long as the profile kernel's;
- this feed cannot exercise wheelchair or bike queries.

**Recommendation:** review the branch, then push it and bump the app's pin. Run the app on the Mac or the Simulator, and keep the profile kernel
behind `ROUTING_KERNEL=profile` until the owner has used the new one.

| | |
|---|---|
| Engine | MobilitéitKit branch `range-mcraptor-kernel` (local, not pushed, head `41534f0`), base `830726a` plus the prototype `fd28443`. Commits: `cbcf317` kernel behind a flag, `fe23a11` tight changes / preferred-mode classes / ties, `cf9fbc7` kernel-specific test expectations, `f5cd2f1` relaxed changes and later rows, `4121c1c` harness timings, `3d2ee1e` publishable fronts in the harness, `daf4e81` stay-aboard walks, `db63ac3` continuations past the window's end, `1d5b10d` range kernel by default, `41534f0` installed worker and shard tests on the profile kernel |
| App | Pin untouched (`c4f4b70`). No app code changed. The pin bump also brings 17 engine commits between `c4f4b70` and `830726a` |
| Network | None. No ATP, relay or walking-service requests. Walks are the harness's deterministic straight-line stand-in |
| Raw results | `equivalence-results.json` (per query: front sizes, missing and gained journeys, timings, published pages), `run.txt` (the six console logs) |

## The staged plan, and where it stands

The prototype write-up (`../range-mcraptor-prototype-2026-11-14/`) proposed five stages:

1. **Kernel behind a flag** (`cbcf317`). `RoutingKernel` (`.profile`, `.rangeMcRaptor`) picks the search a router runs, and the environment variable
   `ROUTING_KERNEL` overrides it. The kernel works on a flat timetable for the window's service days, built per preference variant and cached (a
   small LRU). It runs exact departure iterations with a reused workspace and builds footpaths from the router's transfer-walk table. Arrive-by runs
   the same forward search over the window that ends at the deadline. After the search, a safer-transfer pass picks the change with the most
   slack among equivalent ones.
2. **Constrained transfers and continuations.** Route- and trip-scoped rules (`RangeRaptorTransferRules.swift`), block continuations as chained rows,
   tight-change and preferred-mode classes, and ties on identical twin rows (`fe23a11`).
3. **Realtime overlay and horizon widening.** Each search patches a copy of the timetable (`RangeRaptorOverlay.swift`): delays, cancelled trips and
   closed stops. Rows whose alighting differs are boarded too (`f5cd2f1`). Horizon widening is the session's existing doubling up to 24 hours,
   unchanged.
4. **Equivalence at scale**: this document.
5. **Switch the default** (`1d5b10d`). The profile kernel stays, selectable by flag, until the owner has used the range kernel in the app.
   Delete it only after that review.

## What the harness checks

`RangeRaptorEquivalenceTests` (opt-in, `RANGE_RAPTOR_EQUIVALENCE=1`) draws random stop pairs, service days and times from the installed feed.
Each query also draws one of 8 equally likely preference slots: default (two slots), arrive-by, prefer rail, tight bus changes
(`allowTightSameStopBusTransfers`, 180 s minimum), one transfer at most, wheelchair required, bike required. Optionally it adds synthetic realtime
patches for trips around the query time: delays of up to 15 minutes, running 1–3 minutes early, cancelled trips, and stops closed to boarding and
alighting. Both kernels then run on identical inputs.

- **Fronts.** For each kernel, every candidate is normalised the way a session normalises it (`RaptorWalkingShortcut.normalize`) and checked by
  `JourneyStructuralValidator`. The Pareto front is taken over (departure, arrival, transfers, walking, tight, not preferred). A profile journey is
  **missing** when no range journey equals or dominates it. The gate is missing = 0. `rawMissing` repeats the check on candidates before
  normalisation.
- **Published pages.** Every 10th query also runs two real `JourneyPlanningSession`s, `initialSuggestions(count: 6, searchHorizon: 7200)`, without
  realtime. The two six-journey pages are compared.
- **Timings.** Wall time per query for both kernels, the range kernel's per-stage spans, and its time without the flat timetable build ("warm").
  The harness cycles more service days and modes than the 3-entry cache holds, so most of its range queries rebuild the timetable. Inside a
  session the build happens once.

Setup: feed generation 5 (service 7 October – 12 December 2026, 2,805 stops), the same Mac as the prototype, release build
(`-c release -Xswiftc -enable-testing`), tests run serially.

## Results

Round 3, engine `db63ac3`. Front sizes and missing journeys are counted after normalisation and validation. Gains are range journeys
outside the profile front. Timings are wall time per query; "warm" leaves out the flat timetable build.

| Run | Queries | Empty for both | Profile front | Range front | Missing | Raw missing | Gains | Pages same / different | Profile median / p90 ms | Range warm median / p90 ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| seed 1 | 300 | 116 | 2,378 | 5,102 | **0** | 28 | 3,168 | 15 / 15 | 30.5 / 221 | 8.8 / 92 |
| seed 1, realtime | 300 | 119 | 2,307 | 4,968 | **0** | 20 | 3,082 | 15 / 15 | 33.4 / 218 | 17.1 / 110 |
| seed 2 | 300 | 110 | 2,104 | 3,797 | **0** | 27 | 2,004 | 16 / 14 | 31.4 / 196 | 7.0 / 54 |
| seed 2, realtime | 300 | 112 | 2,033 | 3,667 | **0** | 34 | 1,902 | 16 / 14 | 34.0 / 199 | 14.8 / 71 |
| seed 3 | 300 | 121 | 2,146 | 4,500 | **0** | 26 | 2,777 | 15 / 15 | 27.7 / 207 | 6.8 / 74 |
| seed 3, realtime | 300 | 121 | 2,120 | 4,408 | **0** | 22 | 2,692 | 15 / 15 | 29.0 / 205 | 15.0 / 98 |
| **All** | 1,800 | 699 | 13,088 | 26,442 | **0** | 157 | 15,625 | 92 / 88 | 31.4 / 209 | 11.6 / 84 |

**Raw missing is not zero, and that is expected.** Before normalisation the two kernels' candidates differ in ways the session removes: a
profile candidate that walks where its own trip would have taken the rider has no exact twin in the range kernel, which no longer builds such
walks (bug 3 below). The raw count was 0 before that fix. Every one of the 157 raw differences disappears once both sides are normalised and validated as a session would.

Both full engine suites pass under each kernel: 353 tests in 71 suites, release build, serial, with the default (range) and with
`ROUTING_KERNEL=profile`. The opt-in tests on the installed feed (generation 5) pass under each kernel too:
block continuations, routing-prevention replays, the timetable benchmark, and the replay of three app scenarios. The worker-count and
merge-shard tests check the profile kernel's parallel scan. With the range kernel as the default they had stopped exercising it, so they now run
the profile kernel explicitly (`41534f0`).

The scenario replay (`InstalledEquivalenceReplayTests`, synthetic realtime: delays and a cancellation) gives the same pages for the Esch scenario.
The other two show different journeys, and neither gets worse:
- **Gromscheed → Kirchberg, Konrad Adenauer, departing after 08:00.** The range page swaps one of eight journeys: 08:10 → 08:44 with 740 s of walking becomes
  08:16 → 08:46 with 320 s.
- **Konrad Adenauer → Senningerberg, Gromscheed, arriving by 09:00.** The range page offers later departures for the same deadline: the latest leaves at 08:32:30, against 08:25:00.

### Bugs the harness found, all fixed

1. **A later vehicle reaching a stop sooner on foot hid a relaxed change** (`f5cd2f1`, seed 2 q293). The label that arrived on foot from a later
   vehicle dominated one whose next change would stay relaxed. The bags now also compare when the last vehicle arrived (`incoming`), so a tight
   change never hides a relaxed one.
2. **Only the earliest row was boarded on non-uniform routes** (`f5cd2f1`, seed 1 q25 with realtime). On routes whose rows alight at different stops
   (realtime closures, dead continuations, inert slots, accessibility variants), a later row can reach a stop the earliest cannot. The scan now also
   boards every later row that alights somewhere the boarded rows do not (`boardCoveringRows`).
3. **A walk the normaliser removes could prune a valid twin** (`daf4e81`, seed 3 q80 and 26 other query runs). Seed 3 q80 is Asselborn → Nocher
   at 14:03. Both kernels found 140 to Wiltz Gare routière, a 139 s walk to Pompjeesbau, then the A06 at 15:19:25. The 140 itself reaches
   Pompjeesbau at 15:15:10, so `RaptorWalkingShortcut` replaces the walk with staying aboard. That change then misses its minimum, and the session
   rejects the journey rather than keep the walk, by design. The profile kernel still published the same departure and arrival through a twin:
   140 to Gierwerei, a 220 s walk to Schwemm, A06. The range kernel had pruned that twin, because the 139 s walk dominated it.

   The fix applies the normaliser's rule inside the search (`RangeRaptorStayAboard.swift`): a footpath from a ride is skipped when the same trip
   instance reaches the walk's target after boarding, with set-down allowed, no later than the walk would. The safer-transfer pass skips such walks
   as well. Before the fix, the stricter comparison found **47 missing journeys in 27 of the 1,800 query runs** (16 distinct queries, most of
   them missing both with and without realtime). The raw comparison found none, because both kernels emit the doomed walk. The new regression
   test `rejectedShortcutDoesNotHideALongerValidWalk` fails for the range kernel without the fix and passes for both kernels with it.

   The first version of the fix scanned the rest of the trip for every label and made the range kernel about **6× slower** (warm median 78 ms,
   p90 672 ms, against 12 and 91 ms). The committed version finds once per search which later positions of a route are footpath targets of each
   alighting position, so a label costs a few checks. Its timings match the round before the fix, and its fronts are identical to the slow
   version's.
4. **A continuation was stopped at the window's end** (`db63ac3`, seed 3 q17, with and without realtime). Mersch, Nic. Welter → Neudorf,
   Brasserie at 18:24:31: the window ends at 20:24:31. The missing journey takes the train to Dommeldange, the 25 bus at 20:04, and stays
   seated when the bus continues as line 7, reaching Brasserie at 20:26:50. Both kernels let a rider stay aboard a block continuation only up to
   the window's end, although a trip that is not chained has no such limit. The profile kernel published the journey anyway, by a detour: one of
   its candidates left the bus at Weimershof, Joseph Hackin at 20:23:50, inside the window, and walked on, and the normaliser replaced that walk
   with staying aboard to Brasserie. The range kernel kept no such candidate.

   The fix lets the range kernel ride a continuation to its end once it has left its junction by the window's end, like an unchained trip. The
   cap on leaving the junction stays. The profile kernel is unchanged. The new test `rangeKernelRidesAContinuationPastTheWindowEnd` checks that
   the range kernel reaches the stop after the window's end and that the profile kernel does not.

### Published pages

The harness compares the six-journey pages of two real sessions on every 10th query: 30 per run, 180 in all. The realtime runs repeat the
same queries and pages are compared without realtime, so these are 90 distinct pages counted twice.

- **Identical pages:** 92 of 180. Of the 90 page pairs where either side has journeys, the best journey by the app's quality score (time from the
  query plus 300 s per transfer plus walking seconds) is the same on 88 and better on the range page on 2. It is never worse.
- **Different journeys:** 132 of the profile pages' 484 journeys are not on the range page, and 222 of the range pages' 542 are not on the profile
  page. Every profile journey is still in the range front (missing = 0). The page shows six, and the range kernel fills them with journeys the
  profile kernel never found. Seed 2 q160, Bofferdange → Boevange-sur-Attert at 05:29: after the same first two journeys, the profile page jumps
  to departures from 10:54, each with walking; the range page lists the 07:02, 07:46 and 08:46 departures with one change and no walking.
- **Lower at some rank:** in 8 distinct queries the range page's k-th best score is higher than the profile page's at some rank. A page is not the
  six best scores: it spreads journeys across departure times, and a denser front changes which ones it picks. The best journey is never worse.

Published pages with realtime were not compared.

### Timings

Wall time per query, median / p90 / p99 / max in ms, over all 1,800 queries. The profile kernel runs its parallel pattern scan on 10 workers;
"cold" includes building the flat timetable, which a session does once.

| | Profile | Range cold | Range warm |
|---|---:|---:|---:|
| All queries | 31.4 / 209 / 389 / 628 | 35.8 / 105 / 289 / 794 | 11.6 / 84 / 265 / 771 |
| Non-empty, no realtime (553) | 86.7 / 246 / 396 / 628 | 40.3 / 119 / 308 / 630 | 19.5 / 99 / 287 / 607 |
| Non-empty, realtime (548) | 88.3 / 245 / 395 / 607 | 51.0 / 147 / 376 / 794 | 30.6 / 126 / 354 / 771 |
| Empty, realtime (352) | 7.6 / 15 / 70 / 125 | 32.3 / 47 / 72 / 126 | 9.2 / 12 / 49 / 106 |

By preference profile, non-empty queries without realtime (median warm against profile):

| Profile | Queries | Profile median / p90 | Range warm median / p90 | Median speed-up | Range slower |
|---|---:|---:|---:|---:|---:|
| Arrive-by | 88 | 97.2 / 214 | 13.1 / 56 | 7.0× | 1 % |
| Default | 196 | 110.1 / 228 | 16.7 / 88 | 5.6× | 2 % |
| Tight bus changes | 101 | 108.1 / 314 | 23.4 / 114 | 4.0× | 4 % |
| Prefer rail | 95 | 115.9 / 320 | 39.0 / 165 | 2.6× | 8 % |
| One transfer at most | 73 | 4.2 / 13 | 10.8 / 62 | 0.46× | 67 % |

- **Realtime** adds about 10 ms to the range kernel's median. The overlay copies the whole timetable before patching it.
- **One transfer at most** is the regression: the profile kernel prunes these searches hard, while the range kernel still runs every departure
  iteration.
- **Empty queries with realtime** (no journey either way) cost the range kernel a little more, 9.2 against 7.6 ms median.
- **Tails.** The slowest query is seed 3 q139, Hamilius-Centre (Tram) → Centre, Gruef at 16:11 with rail preferred: 607 ms warm against
  628 ms, and 771 against 607 ms with realtime. Its range front has 389–408 journeys against 75.

## Known limitations

- **Rides cap.** Without a transfer limit the range kernel searches at most 8 rides (7 transfers). The profile kernel has no fixed cap. No query here
  needed more.
- **Journeys that start on a known trip** (`fromTrip`) board only the earliest row of that route.
- **The first search waits for the footpath table** unless `prepareRoutingKernel()` built it earlier. Here it took 23 ms from straight-line walks.
  Its cost from the app's stored transfer walks has not been measured on the phone.
- **Accessibility class** (verified, partial, unknown) is not a label criterion. A wheelchair-required query filters trips and stops before the search.
- **Upstream ties.** Journeys equal on every criterion are kept only at egress stops and on identical twin rows, not at every stop along the way.
  Expanding twins at reconstruction covers the cases seen here.
- **Not measured here:** published pages with realtime (the page comparison runs without it), wheelchair and bike queries (always empty on this feed
  for both kernels, about a quarter of the drawn profiles), and real walking routes instead of straight lines.
- **Cache capacity.** Each router caches three flat timetables (by service days and modes) and six preference variants. A session reuses one.
  Changing the day or the modes between searches rebuilds it, which takes about 20 ms.

## Next steps

1. **Review, then push and bump the pin.** Pushing the engine branch and bumping the app's MobilitéitKit pin need the owner's go-ahead. The bump also
   brings the 17 engine commits already on `main` after `c4f4b70`.
2. **Prepare at launch.** The app should call `TransitRouter.prepareRoutingKernel()` once the router exists, so the first search doesn't wait for
   the footpath table. Until it is ready, a search waits for it (`footpathWait` is nil), so results don't depend on timing.
3. **Try it in the app** on the Mac or the Simulator, with live boards, and compare pages with `ROUTING_KERNEL=profile`.
4. **Work on the two regressions.**
   - Realtime: patch only the rows a realtime batch touches, instead of copying the timetable.
   - One-transfer queries: departure iterations dominate. Pruning iterations by the existing ride bounds is one option to measure.
5. **Delete the profile kernel** after the owner's review: `RaptorSearch` with its compact profile, pattern and reference scans and its
   parallel merge, and the fallback in `RangeRaptor.Engine`.

## Reproduce

In a worktree of MobilitéitKit on `range-mcraptor-kernel`:

```sh
swift build -c release -Xswiftc -enable-testing --build-tests
for seed in 1 2 3; do for realtime in 0 1; do
  ROUTING_BENCHMARK_DATABASE=<generation-5 feed .sqlite> RANGE_RAPTOR_EQUIVALENCE=1 RANGE_RAPTOR_QUERIES=300 \
    RANGE_RAPTOR_SEED=$seed RANGE_RAPTOR_REALTIME=$realtime RANGE_RAPTOR_PUBLISHED_EVERY=10 RANGE_RAPTOR_OUTPUT=<dir> \
    swift test -c release -Xswiftc -enable-testing --no-parallel --skip-build --filter RangeRaptorEquivalenceTests
done; done
```

Each run takes about a minute.
- To print both fronts with legs, every candidate, and both sessions' journey lists with the reasons a page skipped each one, add
  `RANGE_RAPTOR_ONLY=<query indices>`, `RANGE_RAPTOR_CANDIDATES=1`, `RANGE_RAPTOR_HORIZON=<seconds>`.
- The full suite runs with `swift test -c release -Xswiftc -enable-testing --no-parallel` under each kernel: the default (range), and
  `ROUTING_KERNEL=profile`.
- The feed is not in the repository. Generation 5 was copied from the Mac app container.
