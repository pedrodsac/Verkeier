---
doc: routing-speed-plan
written: 2026-10-15
basis: docs/ROUTING_IMPROVEMENT_BRIEF.md, docs/benchmarks/live-baseline-2026-10-15/
app: Verkeier @ refactor/views-and-structure 9110b4a
engine: MobilitéitKit @ c4f4b70 (pinned in Package.resolved)
status: plan; steps 0 and 1 implemented on 2026-10-16, step 2 implemented and measured on 2026-10-18, device replay on an iPhone 13, a live simulator re-baseline (Sunday) and the offline evaluation of CAND-28 on 2026-10-18, CAND-28 live union capture, commit and CAND-5 on 2026-10-19, step 7 live re-baseline, the relay Server-Timing round and the CAND-29 offline evaluation on 2026-10-20 (see "Status after steps 0 and 1" and "Status after step 2")
---

# Routing speed plan

Goal: bring the `live-now` search from 7–10 s to under the 5,000 ms gate
(INV-11), with margin. Target: warm and cold medians ≤ 4,000 ms, every
operation (including priming) < 5,000 ms. Exact steps must keep results
identical (INV-1); product budgets (INV-6) stay fixed.

Identifiers follow the brief: `CAND-n` for candidates. New candidates continue
at `CAND-21`. Refinements of existing candidates keep their brief ID.

## Status after steps 0 and 1 (2026-10-16)

Steps 0 and 1 are done. MobilitéitKit `origin/main` has 5227042 (sub-spans,
warm-up and board timings), 9cdf2c3 (test dates), 9d4a355 (worker-count
test), f258d60 (CAND-25) and f329d01 (CAND-26). The app has the harness commit
f8d42c3 (adds `--replay-latency`) and pins f329d01 in 1f69959; the app branch is
not pushed. No ATP request was sent. All runs replayed the 73 baseline bodies,
each answered after its recorded server wait and transfer time.

| Check | Result |
|---|---|
| `ROUTING_VERIFY_KERNEL=1 swift test --no-parallel` | 309 tests pass |
| INV-1, old vs new engine, generation-6 feed (18 pages) | Byte-identical |
| CAND-23, 1 / 6 / 10 pattern workers | Identical, and equal to the old engine on these queries |
| App replays, before vs after (3 runs each) | Same journeys, recommendation and counters |
| Time from last board to end of realtime phase (≤ 150 ms) | Priming and cold 215–221 → 58–66 ms; warm 165 → 58–60 ms |

**The live baseline is CPU-inflated.** Release build, same M4 MacBook Air.
On the cold sample, live and replay sent the same 27 requests. The stages
that only use the CPU ran 1.5–2.3× slower live than in replay:

| Cold sample, ms | Live | Replay, old engine (median of 2) | Ratio |
|---|---|---|---|
| Snapshot and graph | 875 | 561 | 1.56 |
| `walkingPreparation` (warm-up scan, walks) | 1,260 | 813 | 1.55 |
| RAPTOR pass 1 / pass 2 | 1,148 / 1,351 | 575 / 598 | 2.00 / 2.26 |
| Candidate building 1 / 2 | 343 / 313 | 217 / 212 | 1.58 / 1.48 |
| Realtime phase 1 (network-bound) | 2,563 | 2,269 | 1.13 |
| First render | 366 | 158 | 2.31 |
| Total | 7,655 | 5,235 | 1.46 |

- **Most likely the machine's state, not the live path.** Pass 2 runs after
  the network has finished and was still 2.3× slower. The transfer-walk
  table build, which runs before any search and uses no network, took
  8,013 ms on the baseline day, against 4,780–5,680 ms before each of the six
  replays (1.4–1.7×). Throttling on the fanless Air or background load would
  explain both. The 83–915 ms of client-side request time in §3.6 may be the
  same effect.
- **The numbers in §3, §6 and Checkpoint A are anchored on the live spans.** On
  a quiet machine they are probably too pessimistic. With recorded network
  latency, the steps-0–1 engine replays at about 5.0 s cold and 5.0–5.3 s
  priming. Warm replays at 4.2 s, but this is not like-for-like: replay warm
  fetched 27 boards, live warm 19, because replay did not reuse the cached
  boards. The order of the plan stands. Re-anchor the projections on
  `--replay-latency` medians.
- **Step 1 gained less than §3 suggested.** The old engine's tail is about
  220 ms in replay, not the 640–1,189 ms seen live.
- **Gate measurement (§7, item 5).** Measure on a cool, quiet machine. Record a
  CPU canary with every sample, for example the transfer-walk build time or
  `ProcessInfo.thermalState`. Use `--replay-latency` for A/B runs. Use live
  runs only to confirm.

Still open from step 0: the CAND-30 attribution. The spans needed for it are
now exported. The Block and Lorentzweiler installed tests still fail on
generation 6, because they use dates and trip IDs from an older feed. Step 2
(CAND-11) follows below.

## Status after step 2 (2026-10-18)

Step 2 (CAND-11) is done in MobilitéitKit as four commits on top of f329d01:
676528c (a), eeb4899 (a2), 3d8699f (b) and 2c7575d (c). They are pushed to
`origin/main`, and the app pins 2c7575d in a54a3da (branch not pushed). No ATP request was sent; every run replayed
the 73 baseline bodies with `--replay-latency`.

| Change | What it does |
|---|---|
| (a) Merger task | `Raptor.scanAndMerge` hands out chunks and refills a worker as soon as one finishes. `mergeInOrder` is a separate task that merges finished chunks strictly in index order and releases each one. |
| (a2) Scheduling window | The window of chunks sorted costliest-first is 6 × workers (was 2 ×), and at most one window of chunks may be started and not yet merged (was 3 × workers). See the first finding. |
| (b) Sharded merge | `PatternScanMerge.append` gives each chunk's labels the IDs the serial loop gave (base + earlier chunks + lower stops of the chunk; the shard adds the slot). Stop *s* goes to shard *s* mod *n* (*n* = workers), and every shard merges its stops in chunk order in its own task. |
| (c) Materialize per shard | Each shard builds the labels of its own stops as soon as its last chunk is merged. |

**Findings.** A timeline of every chunk (a scratch instrumented build, not
committed) showed what stalled the scan, and it was not only the serial merge:

- Merging in index order plus a bound of 3 × workers chunks started and not yet
  merged stops the dispatch whenever a slow early chunk holds up the merge. In
  round 3 the scan waited on the merger 7–12 times per scan (13–22 ms in all);
  in the trace read in detail, only 1–2 of the 10 workers ran for 8.5 ms in one
  stretch while the slow chunk 15 finished. The old loop had the same bound, so
  (a) alone gains nothing.
- The costliest chunk of round 3 (46–62 ms, index 105 of 119) started at
  43–45 ms, in the last window, and ended the scan. The chunks add up to about
  700 ms, so 10 workers could finish in about 75 ms; the scan took 100 ms. A
  simulation on the recorded chunk durations (outstanding chunks = window)
  gives 100 ms for a window of 2 × workers, 75 ms for 4 × and 72 ms for 6 × on
  the durations of f329d01 plus (a). On the durations of the final build it
  gives 87 ms for 4 × and 74 ms for 6 ×. In rounds 2 and 4, 6 × is also the
  best (or tied) of 2 × to 8 ×. Peak process memory grew by 7–9 MB (about
  1 %) from f329d01 to (a)–(c) with a 4 × window.
- After (a) to (c), the remaining 5–7 ms of round 3 after the last chunk is the
  shards' last chunks plus their materialize. Before (c), materialize alone took
  15–18 ms (round 3) and 10–12 ms (round 2).

**Metric change.** `merge_ms` used to be the busy time of the serial merge, and
`scan_ms` the wall time minus that. They are now the wall time until the last
chunk finished scanning (`scan_ms`) and the merge time after that point, plus
materialize and continuations (`merge_ms`). Compare `scan_ms + merge_ms`
between engines, not `merge_ms` alone.

**A/B, replay with recorded latency, quiet machine.** Medians over all
authoritative passes of the priming, warm and cold samples (`pass duration` is
the `raptor` span; the warm-up pass is the schedule-only scan inside
`walkingPreparation`). Each run holds all three samples. The six arms alternate,
with the order rotated every round and 40 s between runs. Round 0 of 6 is
dropped; the transfer-walk build (CPU canary) was 1.84–2.15 s in the rest, and
one run above that (sharded engine, round 2, 2.38 s) is dropped. That leaves 5
runs per arm, 4 for (b). Medians of rounds 1, 3, 4 and 5 alone are within 1–3 ms.
Every compared run gave the same journeys, recommendation and counters as the
Base run of its round, apart from the round-3 chunk counters in one warm sample
(see below).

| ms | Base f329d01 | (a) | +(a2) 6 × | +(b) | +(c), final | final with 4 × |
|---|---:|---:|---:|---:|---:|---:|
| Pass duration | 344 | 342 | 337 | 305 | **288** | 292 |
| Pass 1 only | 339 | 336 | 327 | 302 | 281 | 289 |
| Rounds 2+3, `merge_ms` | 88 | 47 | 66 | 38 | 20 | 18 |
| Rounds 2+3, `scan_ms` + `merge_ms` | 175 | 175 | 166 | 140 | **122** | 127 |
| All rounds, `scan_ms` + `merge_ms` | 194 | 194 | 186 | 158 | 140 | 146 |
| Warm-up pass | 429 | 427 | 414 | 392 | 382 | 396 |
| Priming total | 3,894 | 3,892 | 3,902 | 3,799 | 3,751 | 3,771 |
| Warm total | 3,375 | 3,389 | 3,356 | 3,305 | 3,293 | 3,282 |
| Cold total | 3,817 | 3,790 | 3,773 | 3,743 | 3,691 | 3,717 |
| Peak memory, warm sample, MB | 836 | 837 | 847 | 852 | 852 | 844 |

An earlier set of the same kind (4 × window, 6 runs per arm, canary 1.9–2.1 s
in 4 of them) gave pass 342 → 295 ms and rounds 2+3 174 → 128 ms. On a loaded
machine (Low Power Mode on, canary 4.5–10 s, so discarded by the canary rule)
the 6 × window gave pass 584 → 450 ms and rounds 2+3 300 → 178 ms (5 runs per
arm); there (a2) alone gained 79 ms per pass.

**Reading the table.**

- (a) alone changes nothing, as predicted by the first finding. (a2) gains 5 ms
  per pass here (the simulation promised more; it ignores that the merge tasks
  take cores from the scan), (b) 32 ms, (c) 17 ms.
- The 6 × window beats 4 × by 4 ms per pass and 5 ms in rounds 2+3, within the
  noise, for 8 MB more peak memory. It is a separate change so it can be dropped
  or set back to 4 ×.

**Against the step 2 targets.**

- Rounds 2+3 merge ≤ 120 ms per pass: met (20 ms), but not informative. The old
  busy merge was already 88 ms on a quiet machine (154 ms loaded).
- Pass time down by at least the merge share: **not met**. The pass is 56 ms
  shorter (344 → 288) against a merge share of 88 ms. Rounds 2+3 are 53 ms
  shorter. On the loaded machine, 134 ms against 154 ms.
- "Cold pass 1 ≤ 0.9 s" came from inflated live spans. Re-anchored on replay
  medians, pass 1 went from 339 to 281 ms.
- Overall: −143 / −82 / −126 ms (priming / warm / cold, −2.4 to −3.7 %). The
  plan's −0.25 to −0.45 s per pass came from live spans that were 1.5–2.3 × too
  slow.
- What is left: in round 3 the chunks add up to about 700–750 ms, so 10 workers
  could scan in about 75 ms; the scan takes about 82 ms and the merge after it
  about 11 ms. The remaining gap is the costliest chunk, which cannot start
  before its window, and the cores that the shards take from the scan.

**Verification of the four changes** (each stage on its own, in a scratch copy):

| Check | Result |
|---|---|
| `ROUTING_VERIFY_KERNEL=1 swift test --no-parallel` | 311 (a), 311 (a2), 313 (b), 314 (c) tests pass |
| Installed equivalence, generation-6 feed, 18 pages | Byte-identical to f329d01 for every stage, and for 1, 6 and 10 workers |
| Same, with `ROUTING_VERIFY_KERNEL=1` (release, 18 min) | Passes: the sharded merge equals the serial reference merge in every round; output identical |
| `InstalledShardCountEquivalenceTests`, 2 / 3 / 10 / 16 shards × 5 runs | Identical to 1 shard |
| Synthetic chunks, shard counts 1, 3, 10, in-order, reversed, random, one at a time | Same profiles, label IDs and counts as the serial loop; a wrong ID or an unordered merge fails the test |
| Slow merger, 2 / 4 / 10 workers × 1 / 3 / 10 shards | The scan waits at the bound (outstanding = 6 × workers) and finishes |
| Shadow merge in the app: the old serial loop run next to the sharded merge on the same chunks, 100 replays | 2,400 rounds, all identical, including IDs and all three orders |

**One deviation, not from the merge.** In 4 of about 570 replayed samples
(priming or warm; one with the sharded engine, one with only (a) and (a2), two
in the shadow runs) the round-3 chunk counters were 4 higher in both passes
(`retained` 634,519 against 634,515, `label_attempts` +4). Journeys,
recommendation, candidates and all search counters were identical, and the
other rounds and the warm-up scan matched. The shadow runs (merge identical to
the serial loop in every round, including the two deviating runs) place it
before the merge. The walking provider was the first suspect (in 60 identical
replays the routes it returned had different hashes in 19 runs), but it is not
the source: see "Walking provider nondeterminism" below. The cause is a
realtime-matching race, see "Round-3 +4 counters" below. None was seen in about
80 samples of f329d01, which fits a rate of about 1 in 200 samples (here 1 in
208); the code involved is the same on c4f4b70.

### Walking provider nondeterminism (2026-10-18)

**Cause.** The 19 differing hashes are the 8 directed Pafendall funicular
station connections. Their durations, geometry and segments never differ; only
`distanceMeters` does, by up to 9.7 mm (four values). `PafendallFunicularConnection`
sums the ride length with `CLLocation.distance(from:)`, which is not a pure
function: on iOS 27 and macOS 27 it keeps state between calls, so one pair
returns up to 300 ppm apart (123 mm over 2 km) depending on the calls made
before it, on any thread (a lock does not help). The first route computed in a
process is cached by the app and engine, so the variant is fixed per process.

**Evidence.** 171 logged replays of `live-now` on 2c7575d, 38 on f329d01 and 39
on c4f4b70 (instrumented builds, the 73 captured boards, `--replay-latency`): in
every one of them the same 8 of 5,341 pairs differ, with the same three or four
distances (+1.0 mm in about 70 % of runs, −8.7 mm in 22 %, +1.8 mm in 7 %), so
the older engines behave the same. Valhalla gave one raw result per pair and
reach across 311,172 calls and all 4 pool instances; the 250 stored
transfer-walk tables are byte-identical; no cache eviction occurred. The
CoreLocation behaviour reproduces outside the app (`xcrun simctl spawn`).

**Can journeys change?** Not through this. Label dominance and ordering use
seconds and trip keys; walking distance only accumulates into the journey's
displayed distances, and the two journey comparisons that read it
(`JourneySuggestionPolicy`, `sameVehicleChoice`) would need a tie within a
centimetre. INV-1 holds, but the legs' `distanceMeters` are not bit-identical
between processes. The nearest stop to the 120 m and 100 m funicular
classification thresholds is 30 m away, so classification cannot flip today.

**Fix (uncommitted).** `GeodesicDistance` (pure Vincenty, deterministic
fallback) replaces `CLLocation.distance` in the funicular connection, the route
search distance and the nearby-stop prefilter. A new test fails today (200 of
200 funicular routes differ after unrelated distance calls) and passes with the
fix; the full suite (312 tests) passes. The funicular distances move by 0.2 mm;
durations are unchanged and nothing stored contains a funicular route, so no
`algorithmRevision` bump. Details: `walking-provider-nondeterminism.md` in the
side-session notes.

**The +4 is not from walking.** One deviating run was caught (priming sample,
1 of 148 on 2c7575d): its 5,341 walking results and all 15 batch sizes were
identical to a normal run's, and only `label_attempts` and `retained` of round 3
(both passes) were +4 (`alights`, `boarding_checks`, `feasible_boardings` and
`rejected_before_allocation` were equal). Its cause is below.

### Round-3 +4 counters (2026-10-18)

**Cause.** A wrong realtime match plus a timing race, both in the engine's
realtime layer. The board of stop 000200417025 holds two Bus 18 rows one minute
apart in opposite directions (`1|560|15` to Kirchberg 19:35:00, `1|623|2` to
Kockelscheuer 19:36:00). `uniqueCandidate` gives both the same GTFS trip,
24361759 (the second row's passlist has 1 of its 25 stops on that trip), so the
trip gets two `reported` departures at that stop, 19:35:00 and 19:36:00. Equal
rank is decided by the observation time, which is the board's request start
(`DepartureBoardCache`), microseconds apart between boards started together: a
scheduling race. The wrong 19:36:00 won in 1 of 208 unforced samples (the +4
sample); the right 19:35:00 won in the other 207, all with the usual counters.
With the wrong one, chunk 110 of round 3 keeps 4 more temporary labels
(`attempts` 233,420 → 233,424), most likely through the 60 s larger transfer
slack in the dominance key; the cross-chunk merge removes them, and merged
labels, IDs, later rounds, journeys and recommendation are identical. A second
pair (tram T1 on stop 000200417046, trip 24445480) flips in about half of all
samples and changes no counter.

**Evidence.** An instrumented scratch engine logs the patch set, the input
labels, the active instances, the walking requests and routes and every chunk's
counters per round. Across 104 replays (208 samples) only those 4 events vary.
Forcing the 19:36:00 departure (`ROUTING_SCAN_OVERRIDE`) reproduces `634519 /
4842370` in rounds 3 and 7 in every forced sample (6 of 6) and nothing else
differs. Forcing the two other order-sensitive events (stop 000200417023 of
the same trip, 000200417052 of the tram) changes nothing, and the tram's two
values at 000200417046 (about half and half in the 208 samples) never move a
counter. The natural flip and the forced ones have the signature of the
original catch.

**Journeys.** Not affected. INV-1 holds; the two counters are not bit-stable
while these rows exist, so a sample with the same +4 in `rounds[2]` and
`rounds[6]` is this race and may be dropped from a counter comparison.

**Fix (scratch clone, not applied).** `engine-direction-guard.patch` in the
side-session notes: a row whose destination contradicts the trip's headsign
needs two passlist stops on the trip, as a cancelled row already does. The new
engine test fails without it and passes with it; the full engine suite (315
tests, serial, kernel verification on) passes. With it, 16 replayed samples
have the usual counters, no varying event and no order-sensitive merge (8–10
per run before), identical journeys, and `matchingRejections.noCandidate` = 2
(the two wrong rows). A real disagreement between two boards would still be a
microsecond race; see the notes for a stable tie-break. Details:
`round3-plus4-deviation.md`.

### Device replay, iPhone 13 (2026-10-18)

Release `ROUTING_BENCHMARK` build of app d72dada (engine 1779b82, walking
graph bundled) on the owner's iPhone 13 (A15, 6 cores, iOS 27.0.1).
`Scripts/benchmark_routes_device.py` replays the 73 baseline bodies with
recorded latency at the baseline epoch, using the generation-6 feed under its
simulator file name. Each round has four launches: a container probe, a
transfer-walk build (CPU canary), priming plus warm, and cold. No ATP request
was sent; the request budget is 0, and a launch without capture bodies or with
a missing query fails. 5 rounds with 40 s between them. Every sample started and
ended in the `nominal` thermal state with Low Power Mode off, so none was
dropped. All 15 samples have identical journeys, recommendation, search counters
and canonical plans, also against the simulator round. Only the chunk-local
round counters (`retained`, `label_attempts`, `feasible_boardings`,
`rejected_before_allocation`) differ from the simulator, because they follow
the worker count (6 against 10). The phone's transfer-walk table is
byte-identical to the simulator's.

Simulator columns: two like-for-like rounds at the same pin on a quiet
machine (canary 2.10 and 1.84 s). Their totals are 3,805–3,865 / 3,255–3,261 /
3,695–3,705 ms (priming / warm / cold), in line with the step 2 medians of
3,751 / 3,293 / 3,691 ms.

| Per-sample total, ms | Round 1 | 2 | 3 | 4 | 5 |
|---|---:|---:|---:|---:|---:|
| Priming | 4,875 | 4,837 | 4,825 | 4,792 | 4,747 |
| Warm | 4,165 | 4,156 | 4,197 | 4,191 | 4,122 |
| Cold | 4,795 | 4,771 | 4,774 | 4,981 | 4,737 |
| Transfer-walk build (canary) | 4,237 | 4,274 | 4,174 | 4,222 | 4,256 |

| Median, ms | iPhone priming | warm | cold | Simulator priming | warm | cold |
|---|---:|---:|---:|---:|---:|---:|
| Total | **4,825** | **4,165** | **4,774** | 3,835 | 3,258 | 3,700 |
| Before the live phase (snapshot, endpoints) | 605 | 4 | 598 | 348 | 3 | 342 |
| `snapshotPreparation` | 425 | 1 | 429 | 259 | 0 | 256 |
| Live phase 1 (network-bound) | 2,103 | 2,071 | 2,060 | 2,080 | 1,970 | 1,998 |
| Its tail after the last board | 65 | 62 | 64 | 33 | 32 | 34 |
| `walkingPreparation` (warm-up scan, inside phase 1) | 763 | 673 | 758 | 425 | 320 | 380 |
| RAPTOR pass 1 / pass 2 | 603 / 619 | 596 / 613 | 611 / 628 | 294 / 290 | 279 / 290 | 278 / 291 |
| Candidate building 1 / 2 / 3 | 195 / 178 / 174 | 183 / 179 / 180 | 207 / 185 / 181 | 108 / 109 / 108 | 101 / 106 / 107 | 108 / 107 / 109 |
| Wave 1 (one board) | 454 | 462 | 445 | 426 | 439 | 438 |
| After the last build (assembly, render) | 85 | 63 | 85 | 180 | 64 | 137 |
| First render | 55 | 38 | 57 | 156 | 47 | 114 |
| Peak memory, MB | 503 | 510 | 505 | 798 | 811 | 799 |

**Reading.** The phone passes the 5,000 ms gate in all 15 samples, but only
just: the slowest priming sample took 4,875 ms and the slowest cold one 4,981
ms. It misses the plan's targets (warm and cold medians ≤ 4,000 ms, maximum ≤
4,500 ms) with 4,165 ms warm and 4,774 ms cold. The live phase is network-bound
and takes about as long as on the simulator (2.06–2.10 s against 1.97–2.08 s).
The CPU-bound stages run 1.6–2.2× slower: a RAPTOR pass takes 0.60–0.63 s in the
medians (simulator 0.28–0.29 s), a candidate build 0.18 s (0.11 s), and priming
and cold spend 0.6 s before the live phase starts (0.35 s). The warm-up scan
(0.67–0.76 s) stays hidden inside the live phase. After the live phase the phone
needs about 2.1 s (simulator 1.3–1.4 s), and 1.57–1.60 s of that is the two
passes and their builds. The second pass with its wave-1 board and build takes
1.25 s on the phone. Subtracting it gives about 3.6 s priming, 2.9 s warm and
3.5 s cold on these replays, so CAND-28 alone would meet the targets. A given
kernel speed-up saves about twice as much on the phone as on the simulator, but
exact CPU work on its own would have to remove about 0.8 s per cold search,
roughly half of both passes and both builds; step 2 gained 56 ms per pass. Steps
3–4 therefore cannot reach the targets alone on the phone, but they widen the
priming and cold margin to the gate. Their acceptance numbers (pass ≤ 0.65 s,
warm-up ≤ 1.1 s, build ≤ 0.2 s) are already met by the phone's medians, because
they came from the inflated live spans. Replay leaves out the client-side
request time seen live (§3.6), which is probably larger on the slower CPU, so
live searches on the phone will be slower than these replays.

### Live re-baseline, simulator (2026-10-18, Sunday)

Approved by the owner: 3 live rounds of priming, warm and cold on a quiet
machine. Release build at 60b0c97 with engine 1779b82. CPU canary 1.88–2.02 s.
243 ATP requests (81 per round). Results and method are in
[`benchmarks/live-2026-10-18/`](benchmarks/live-2026-10-18/README.md).

**Sunday caveat.** The searches ran on Sunday evening at 18:32–18:34. The
inputs were lighter than the Thursday 17:51 baseline: 6.4–6.6 MB of boards
instead of 17.9 MB, and passes of 130–184 ms instead of about 290 ms in the
weekday replays. The totals below are therefore not a weekday gate verdict.

| Live, ms | Round 1 | 2 | 3 | Median |
|---|---:|---:|---:|---:|
| Priming | **5,657** | 3,161 | 2,778 | 3,161 |
| Warm | 2,110 | 1,905 | 2,407 | 2,110 |
| Cold | 2,961 | 2,183 | 3,697 | 2,961 |

Each sample's request times, from the URLSession timestamps:

| Per request, ms | Median across samples | Maximum |
|---|---|---:|
| App start of the request → request sent | 1–27 | 31 |
| Request sent → first byte (relay plus ATP) | 837–1,600 | 4,427 |
| First → last byte | 7–290 | 584 |
| Live phase end after its last board | 1–14 | 14 |

- **The client-side request time in §3.6 was machine load.** On a quiet
  machine, the app sends every request within 31 ms of starting it. The busy
  baseline took 83–915 ms. CAND-30 needs no code change. Only CPU contention on
  slower hardware could bring it back, which the device replay cannot show.
- **Live CPU matches replay on a quiet machine.** Replays of the same captures
  gave a median pass of 133 ms against 135 ms live, and a median candidate build
  of 105 ms in both. The 1.5–2.3× inflation of the baseline was the machine's
  state, not the live path.
- **The relay and ATP response time now dominates.** The first live phase took
  1.2–4.5 s of each search, and everything after it 0.54–0.75 s. The one sample
  over the gate, priming in round 1, waited 4.4 s for its slowest response.
  Its other requests had a median server wait of 1.6 s. The relay's
  `Server-Timing` header (§7, item 3) would show how that splits between the
  Worker and ATP.
- **The second pass still runs in every sample.** CAND-28 remains the largest
  item the app controls.
- **Still needed for a gate verdict:** a weekday evening run, ideally on the
  iPhone. The device script only replays today.

### CAND-28, offline evaluation (2026-10-18)

CAND-28 is implemented in MobilitéitKit on top of 1779b82 and was first
evaluated without any ATP request. On 2026-10-19 the owner chose to commit it
without an iPhone measurement: MobilitéitKit `d8635e5` (pushed), pinned by the
app in `1634386`. The 320 serial tests pass on 1779b82 plus only these files. The
replay harness's approximate mode is committed in the app as `859c7f3`.
Details, method and files:
[`benchmarks/cand-28-offline-2026-10-18/`](benchmarks/cand-28-offline-2026-10-18/README.md).

- **Change.** A selected ride that boards after another ride is requested with
  its own line plus every line `realtimeTargets` names at that stop, and those
  lines' trips are added to `tripIDs`. Speculative completion and waves. Same
  windows and stops; the first ride's board is unchanged.
- **Engine.** 5 new tests (a Héienhaff-like fixture where the delayed
  connecting line is only on the transfer stop's board, waves and speculative
  completion, unnamed line, staying aboard). Full serial suite with
  `ROUTING_VERIFY_KERNEL=1`: 320 tests pass.
- **New queries.** In all 4 captures exactly two boards change: Héienhaff
  (`16` then `6` become 6 lines) and Luxexpo (`21,6` becomes 33 lines on
  Thursday, 16 on Sunday). The replay answers them from recorded boards of the
  same stop and window (`--replay-approximate`, labelled approximate): rows
  exist for 2 of the 6 and 2 of the 33 (16) lines.
- **Passes, requests, bytes.** 36 pairs of samples (Thursday plus 3 Sunday
  rounds, ×3 runs, priming/warm/cold): **2 passes become 1 in every sample**;
  journeys, recommendation and live coverage identical in all 36 pairs; every
  Base query is covered by a CAND-28 query (INV-6). `networkRequests` 27 → 26
  on Thursday (27 on Sunday, where wave 1 was a cache hit: pass 2 there came
  from matching trips that the speculative call had not been asked for, which
  `tripIDs` now covers). Estimated `responseBytes` **+17 % Thursday, +14 %
  Sunday** (the two wider boards: +3.1 / +0.9 MB).
- **Time (simulator, replay).** Thursday −0.9 / −0.8 / −0.8 s (priming / warm /
  cold) if the wider boards answer as fast as the narrow ones did; −0.4 / −0.3 /
  −0.2 s with a modelled 1.15 s and 1.85 s; break-even about 2.0 s per board
  (+0.3 to +0.9 s at 2.2–2.4 s). Sunday −0.05 to −0.4 s (cheap passes). **The
  open question is the live latency of the two wider boards**, which no replay
  can show. On the iPhone the dropped second pass is worth 1.25 s, so the
  break-even should be higher; not measured.
- **What can change live, and why.** The transfer boards are wider (the point);
  journeys can differ when an extra line has live data routing uses (a delayed
  or cancelled connection seen in pass one instead of never or in a wave); never
  more stops or windows than today. Not covered: a connecting vehicle scheduled
  before the selected ride's window start, as today.
- **Live union capture (2026-10-19, Monday 18:43).** 81 ATP requests (cap 120):
  `live-now`, `live-reverse`, `live-esch`, one CAND-28 priming search each, both
  arms then replayed from that capture
  ([`benchmarks/cand-28-live-2026-10-19/`](benchmarks/cand-28-live-2026-10-19/README.md)).
  **One authoritative pass in 3 of 3**, but Base already needed one on two of
  them, so the pass is saved on `live-now` only (2 → 1, requests 28 → 27, about
  −0.3 to −0.6 s on the simulator; 3,131 ms live). Journeys, recommendation,
  live coverage identical on all three; every Base query is covered (INV-6).
  Bytes +16.5 % and +22 % where a hub board widened, 0 on `live-esch`. The wide
  boards' live wait + transfer: Luxexpo 33 lines 1.23 s (110 rows) and 1.75 s
  (155 rows), Héienhaff 6 lines 1.30 s, against a median board of 0.5–0.9 s and
  the ≈ 2.0 s break-even. Not measured: Base live on the same minute, the phone,
  a second evening. Step 5 acceptance met on this sample (≥ 2/3 one pass,
  requests ≤ +20 %, no coverage loss) except "`responseBytes` not higher", which
  CAND-28 breaks by design.

### CAND-5, persisted routing snapshot (2026-10-19)

CAND-5 is implemented in MobilitéitKit on top of `d8635e5` and wired into the
app. The engine change is `83ecb6b` (pushed to `origin/main`); the app pins it
in `b6e0ff3` and wires the cache in `3523dcb` (both on
`refactor/views-and-structure`, not pushed). These docs are uncommitted. No ATP
request was sent. Numbers, method and per-run data:
[`benchmarks/cand-5-snapshot-2026-10-19/`](benchmarks/cand-5-snapshot-2026-10-19/README.md).

- **Change.** `TransitRouter` and `JourneyPlanner` take an optional
  `snapshotCacheDirectory`. The snapshot is stored there as one file,
  `routing-snapshot.bin`: magic and format version, the feed identity, an XXH64
  checksum, then 8-byte-aligned little-endian columns read in place from a
  mapped file. It holds the tables the build produces and its expensive indexes
  (pattern grouping, departure-stop and occurrence indexes, nearby-transfer
  stops, continuation sources); lookup dictionaries, station groups, rule groups
  and the service-day instants are derived on load by the same code the build
  uses (the instants follow the running OS's time-zone database, so they are
  not stored). **Identity** is the format version plus the database's file name,
  size, modification time, SQLite header (change counter, schema cookie) and the
  feed metadata (dates, generation, schema version); the path is left out so a
  moved container keeps its file. Any mismatch, a bad checksum, a truncated or
  unknown file falls back to the build, which rewrites the file atomically
  (`Data.write(.atomic)`) in a `.utility` background task after the router is
  ready. A value the columns cannot hold exactly (a 32-bit overflow, say) means
  no file is written, never a lossy one. `JourneyPlanner.removeSnapshotCache(in:)`
  deletes the file; the app calls it when a new feed is installed, and the file
  lives in `Caches/Mobiliteit/RoutingSnapshot`. One file per directory: a new
  feed or format replaces it.
- **Builder change.** The build now sorts each stop's service/route list (it
  was a `Set`'s per-process order; its only reader collects it into a `Set`), so
  the snapshot and the file are reproducible. The derivations moved into
  `SnapshotDerivedIndexes`; the snapshot component structs are `Equatable`.
- **Guards against a stale file after a code change.** `RoutingSnapshotCodec.formatVersion`;
  a golden-digest test that fails when the stored bytes of a rich fixture
  change (the signal to bump the version); a test that lists every stored
  property of `RoutingSnapshot` and fails when one is added, so the codec and
  the comparison cannot silently miss it (the codec also builds the snapshot
  through its memberwise initializer, which stops compiling).
- **Exactness.** (1) `loaded == built` for every table and index routing reads
  (24 fields, byte-exact strings), on a fixture that reaches parent stations,
  canonically equivalent names, non-consecutive sequences, empty times, stop
  headsigns, pickup/drop-off restrictions, blocks, in-seat rules, pathways with
  and without optional values, exact-times frequencies and service past midnight,
  and on the real 28,006-trip feed. (2) A 26-part digest of the snapshot from
  HEAD's builder, from the refactored builder, and from a file loaded in a new
  process is identical. (3) `InstalledEquivalenceReplayTests` JSON, 1.26 MB:
  byte-identical for HEAD, CAND-5 built and CAND-5 with every snapshot loaded
  from the file (the test takes `ROUTING_EQUIVALENCE_SNAPSHOT_CACHE`). (4)
  `ROUTING_VERIFY_KERNEL=1 swift test --no-parallel`: 342 tests, 68 suites pass
  (22 new: format, damage at any byte or length, version, identity, a moved
  container, a rewritten database, an unwritable directory, concurrent starts,
  misaligned memory, planner wiring). (5) The app's integration suite, with a
  new restart test, passes against the engine.
- **Size and load.** 17,613,944 bytes (17.6 MB) for 641,398 stop times. On the
  host: build 226–252 ms, load 13–19 ms (identity check 0.3 ms), encode 30 ms,
  write 33 ms.
- **Replay A/B (simulator, 3 routes × 5 reps × 2 arms, alternating, canary
  filtered).** Cold `snapshotPreparation` **244 → 22 ms** (target ≤ 300 ms; the
  baseline already met it in these replays, so the 866–916 ms of row 14 is not
  reproduced here); priming 248 → 45 ms. The live phase starts at 114 ms
  instead of 315 ms: **cold total 2,959 → 2,786 ms (−173), priming −199, warm
  unchanged (+15, noise)**, a little under the −0.25–0.35 s of the projection
  because graph and endpoint preparation are now the limit, as predicted.
  Journeys, recommendation, canonical plans and counters identical in every
  pair (one `live-esch` recommendation switch, at the same minute in both arms,
  is the wall-clock `now`). First start (file missing): priming 286 against 282
  ms for Base, the file is ready before the next process. Not measured: the
  iPhone (the stage was 429 ms there, so the gain should be larger), a feed
  update on a device. The MacBook ran on battery power for this series (arms alternated).
- **Open.** Step 6's remaining items are untouched. Since this was written, the
  app has been built against the remote pin: the 342 engine tests pass on a clean
  copy of `83ecb6b`, and the app (`3523dcb`, pushed) builds against it.

### Step 7 live re-baseline, simulator (2026-10-20, Tuesday)

This run uses everything committed so far: steps 0–2, the direction guard,
`GeodesicDistance`, CAND-28 and CAND-5 (app `3523dcb`, MobilitéitKit
`83ecb6b`). Details and data:
[`benchmarks/step7-2026-10-20/`](benchmarks/step7-2026-10-20/README.md).

- **Set-up.** 3 rounds of priming, warm and cold on a quiet M4 on mains power,
  240 ATP requests in all. Round 1 ran at 18:52 and rounds 2 and 3 at
  19:05–19:06, after a script bug stopped the first start. Canary 2.2–2.7 s.
- **Totals, ms:**

  | Sample | Round 1 | Round 2 | Round 3 | Median |
  |---|---:|---:|---:|---:|
  | Priming | 2,914 | 5,490 | 4,959 | 4,959 |
  | Warm | 2,141 | 4,792 | 7,480 | 4,792 |
  | Cold | 2,562 | 4,629 | 3,909 | 3,909 |

- **Gate: fails.**
  - 2 of 9 operations are over 5,000 ms.
  - The warm median is 4,792 ms; the cold median of 3,909 ms passes.
  - The warm maximum is 7,480 ms and the cold maximum 4,629 ms.
  - Round 1 alone passes everything.
- **The client side is done for this route.**
  - One authoritative pass in 9 of 9 samples, so pass 2 is gone.
  - Scan 219–302 ms, `snapshotPreparation` 0–90 ms, `walkingPreparation`
    242–356 ms.
  - Total minus the realtime stage is 0.4–0.8 s.
  - Journeys and live coverage are complete, and the replays reproduce every
    journey and recommendation.
- **The misses are server time.**
  - In rounds 2 and 3 the median server wait per board rose from 0.4–1.1 s to
    1.5–3.7 s, and transfer from 14–20 ms to 0.2–1.0 s. This hit every board,
    single-line ones included.
  - The 33-line Luxexpo board that CAND-28 widens was the slowest board in 5 of
    the 6 slow samples, at up to 4.0 s wait plus 2.6 s transfer. But in the
    7.5 s sample the next boards took 6.5 and 6.3 s, so a narrower board would
    not have saved it.
  - Whether ATP, the relay or rate limiting caused this cannot be told from the
    client.
- **What could still move the gate** (all need the owner):
  - A relay `Server-Timing` header to locate the wait (§7, item 3).
  - Routing-only relay trimming (CAND-12 a), which cuts the transfer share.
  - Narrowing hub boards (CAND-28b).
  - CAND-29. As specified it would not help; see its *Evidence* bullet in §4.5.
  - A gate that accepts the server's tail, for example measuring it apart from
    client time.
  - A tighter acquisition budget, which would change INV-6.

  The exact client steps (3, 4 and 6) can only shave a few hundred ms.
- **Server-Timing (added 2026-10-20).** The relay sends
  `Server-Timing: upstream;dur=…;desc="headers", edge;desc="<colo>"`. It was
  committed as `verkeier-relay` `f9c9f75` (pushed) and deployed as version
  `aef3e2b5`. The engine records it with each request's metrics (`00078b6`),
  and the app pins that revision (`def57ca`). `benchmark_routes.py` (`af2180a`)
  writes a `relaySplit` per sample: the upstream wait and the rest, which is
  relay plus network. Body transfer is streamed and is not split.
- **First live split (20:57, one round, 78 requests, on battery).** See
  [`benchmarks/server-timing-2026-10-20/`](benchmarks/server-timing-2026-10-20/README.md).
  - ATP's wait for the response headers is about 80–85 % of each board's
    server wait: median 402–604 ms, maximum 794–910 ms.
  - The relay and network add a median of 70–117 ms (maximum 282 ms),
    through Cloudflare FRA.
  - Totals were 3,161 / 2,037 / 2,437 ms, with 2 passes each.
  - ATP was fast at that hour, so a run in a slow period is still needed to
    explain the 19:05 rounds.
- **Why that round ran two passes (offline replay, no ATP).** See
  [the write-up](benchmarks/server-timing-2026-10-20/README.md#why-each-sample-ran-two-passes).
  - Pass 0 picked bus 29 to Héienhaff and then the T1. Discovery's 24 boards
    did not include the Héienhaff P+R T1 stop (`000200508005`).
  - The check after pass 0 fetched that board. ATP's whole-minute times
    moved every tram 50 s earlier than GTFS (the rule since `60af526`), which
    counts as a routing change. Pass 2 then dropped the now-infeasible
    connection.
  - Pass 2 cost 0.45–0.69 s per sample. With that one board added to discovery,
    a replay ran one pass with identical results and the same 26 requests,
    about 0.5 s faster.
  - This shows the cause, not a fix. CAND-29 as specified would not fetch
    that board: see its *Evidence* bullet in §4.5 and the
    [CAND-29 offline evaluation](benchmarks/cand-29-offline-2026-10-20/README.md).
    Minute precision also makes nearly every new board a routing change: all
    130 trips in the first batch were.

## Summary

### What the code and the baseline show

1. **The second pass is caused by one board that was fetched for the wrong
   line.** In all three samples, wave 1 fetched one board: Senningerberg,
   Héienhaff (`000200508016`) for line 6. The speculative completion had fetched
   the same stop 2–4 s earlier for line 16 only. ATP passlists start at the
   board stop (true for all 2,354 departures in the 73 captured boards), so the
   line-6 boarding at Héienhaff could not come from any other board. Wave 1
   changed routing inputs, so pass 2 and another build ran: 1.4–1.7 s, plus the
   0.35–0.44 s wave.
2. **Discovery spends most of its boards next to the destination.**
   Discovery orders frontier stops by remaining rides, then distance to the
   destination. It uses walking-chain reachability, and with walking chains the
   whole corridor counts as "zero rides" from the destination. So the order
   falls back to distance. In priming and cold, 16 of the 24 discovery boards
   were stops 0–1,249 m from the destination (warm: 8 of 16). They are also the
   largest and slowest boards: 75 % of all decoded bytes, median 1.49 s against
   1.03 s for origin-side stops. The transfer stop Héienhaff was never chosen.
3. **In cold and priming, the live phase ends 0.6–1.2 s after the last
   response.** Matching only starts after the slowest board. The speculative
   call also clears the provider's matching memo while discovery is still in
   flight. The warm sample had no such overlap and its tail was 54 ms.
4. **In the warm sample the network was not the bottleneck.** The critical path
   there was the schedule-only warm-up scan (2.1 s), then a preliminary build
   (0.5 s), then the speculative fetch. All discovery boards had arrived 1 s
   before the speculative fetch ended.
5. **The merge stalls the workers.** The serial merge runs on the same loop
   that hands out new chunks, so finished workers sit idle while it runs.
   Rounds 2 and 3 take 0.55–0.9 s of every pass, and about half of that is
   serial merge time.
6. **Pass 2 mostly repeats pass 1.** In rounds 1–3 the alighting checks and
   retained labels are identical in both passes, and in round 4 they differ by
   4–7 labels.
7. **63 % of board bytes are fields the engine never reads** (71 % if the
   unusable passlist `id` is included). Trimming them cuts the 73 boards from
   46.4 to 13.5 MB decoded, and from 4.46 to 0.76 MB gzip. The latency gain is
   small, though: the main costs are server wait and CPU, not transfer.
8. **Each discovery request spends 83–915 ms on the client, outside queueing,
   server wait and transfer.** This time is largest when the CPU is busy.
   Requests made while the CPU was idle spent 1–3 ms there.
9. **Results probably depend on the number of CPU cores.** The scan is split
   into `min(10, cores) × 12` chunks, and each chunk evicts labels before the
   merge. A 6-core iPhone may therefore return different journeys than the
   10-core Mac simulator. This needs one test to confirm.

### Recommendation

Exact work alone is not enough. Run it first because it is risk-free and makes
every later step cheaper. Then one small live change removes the second pass.

| Step | Class | priming | warm | cold |
|---|---|---:|---:|---:|
| Baseline (n = 1) | — | 10,058 | 7,053 | 7,655 |
| Exact steps 1–4: kernel, candidates, provider | exact / replay-exact | ≈ 7,200 (6,600–8,200) | ≈ 4,500 (4,100–5,100) | ≈ 5,400 (4,900–6,100) |
| + no second pass (CAND-28) | live | ≈ 6,000 (5,600–6,800) | ≈ 3,400 (3,200–3,800) | ≈ 4,200 (3,900–4,600) |
| + transfer-first discovery (CAND-29), persisted snapshot (CAND-5) | live / exact | ≈ 5,200 | ≈ 3,100 | ≈ 3,600 |
| + priming items (CAND-30, CAND-31, CAND-14) | mixed | ≈ 4,300–5,000 | — | — |

These figures come from a critical-path model built on the baseline spans, not
from measurements (§6). Warm and cold can reach the target with margin, but
only if the second pass is avoided. Priming stays close to the gate until the
client-side request time is explained (CAND-30), or the owner accepts warming
the router and walking graph before the first search (CAND-31).

---

## 1. Method and limits

- Read: brief, `AGENTS.md`, `docs/ROUTE_CALCULATION_PERFORMANCE.md`, all engine
  files the brief cites (`TransitRouter.generate`, `Raptor*.swift`,
  `JourneyPlanningSession+*Realtime*.swift`, `HafasRealtimeRoutingProvider*.swift`,
  `DepartureBoardCache`, `MobiliteitAPIClient` models, quality policies) and the
  app's adapter, refinement and benchmark harness.
- Re-derived the timeline from `samples.json`. Request start times use a
  different clock from the spans, so they were aligned using the wave-1 request,
  which must fall inside the wave-1 `realtime` span (accurate to about ±20 ms).
- Ran read-only SQL against the installed generation-6 database in the
  simulator container, to check §2.1 and to rebuild the nearby-stop graph
  offline.
- Analysed the 73 baseline response bodies, which are still in the simulator's
  `tmp/routing-network-capture` (matched by `receivedAt`). This made no network
  requests.
- No source edits, no `xcodebuild`, no ATP request.

Exactness classes used below:

| Class | Meaning | How verified |
|---|---|---|
| Exact | Same inputs → bit-identical candidates, journeys, IDs, recommendation | `ROUTING_VERIFY_KERNEL=1 swift test --no-parallel`, `InstalledEquivalenceReplayTests`, app replay + `compare_route_benchmarks.py` |
| Replay-exact | Identical given identical recorded boards and clock; live runs differ only where a time deadline binds today | App replay |
| Live | Changes which boards are requested; results may differ | Owner-approved live A/B runs and quality review |

Confidence: **high** means the mechanism is clear in code and the size is
bounded by measured numbers. **Medium** means the mechanism is clear but the
size is inferred. **Low** means an unmeasured hypothesis.

---

## 2. Corrections to the brief

Claims checked against code at `c4f4b70` and the baseline data. Everything not
listed was confirmed. That includes all §2.1 counts, using read-only SQL on
generation 6: 2,805 stops; 709 bus, 5 rail and 1 tram routes; 28,006 trips;
641,398 stop times; 1,748 patterns; 2,904 rules (2,668 type 2, 236 type 1, 213
scoped); 2,691 stops with rules; 2,660 blocks; no pathways or frequencies; max
time 102,030 s. It also includes the control flow in §4 (at most 2 waves and 3
authoritative scans), the §6 thresholds, the §8 constants, §9.2 (identical
results in all samples), and the §9.3 and §9.4 numbers.

| # | Brief | What the code / data says | Why it matters |
|---|---|---|---|
| 1 | §5.4 rule tie-break: "then later row" | `max(by:)` ends with `$0.order > $1.order`, so the **earliest** row (lowest `order`) wins | CAND-1's fast path must reproduce this |
| 2 | §5.5 dominance "one strict" | In both the compact (`ScanKey.dominates`) and reference (`Raptor.dominates`) kernels, the final disjunct is always true for same-chain labels. **Equal labels dominate, so the first one inserted survives** | Insertion order is part of the result. Any reordering is not exact |
| 3 | §4.2 step 4, §9.3, CAND-13: speculative completion "with ≤4 requests", in parallel with discovery | ≤4 **concurrent** requests. It starts only after the warm-up scan **and** a preliminary build (`generate`, lines 852–870). In the warm sample this chain was the critical path | §3.1, CAND-10, CAND-28 |
| 4 | §9.4: continuations "outside `merge_ms`" | `relaxContinuations` runs between `mergeStarted` and `mergeMilliseconds`, so it is **inside**. Pathways are outside (a no-op on this feed) | Attribution only |
| 5 | §9.4 "Merge costs as much as the parallel scan" | `scan_ms` = task-group wall time − merge time. The merge runs on the loop that enqueues chunks, so workers idle while it runs. The two numbers are coupled | CAND-11 should be expected to save more than `merge_ms` alone |
| 6 | §9.4 walking: "mostly cache hits: 27,827 requests, 22,327 hits" | The counters cover the whole `generate`: endpoints, direct walk, warm-up and both passes. Only about 3,000 unique pairs are looked up per round. The 260 ms per pass is more likely the serial bookkeeping for every (label × target) pair | CAND-21. Measure first |
| 7 | §9.5 "Every request covered 150 minutes" | 49 requests covered 17:30–20:00 (150 min) and 24 covered 18:00–20:00 (120 min). All ended at 20:00 (the 2 h window to 19:51, rounded up to 30 min) | — |
| 8 | §9.5 "Latency is dominated by server wait" | Partly. Discovery requests also spent 83–915 ms client-side, outside queue, server wait and transfer (median 236 ms over all 73). "Server wait" is itself measured on the client | CAND-30 |
| 9 | §6.2 frontier "rides to destination, distance to destination" | With `allowWalkingChains: true` (kept deliberately in `ac6945e`), the zero-ride set covers the corridor: 548 stops against 92 with one walking batch. This comes from an approximate offline rebuild of the nearby-stop graph, with egress taken as alightable stops within 1.5 km. Both Héienhaff and Gromscheed count as "zero rides" from Kirchberg, so ordering is by distance to the destination | CAND-29 |
| 10 | §6.4 "Stops ordered by cached coverage" | Only with `.useCache`. The benchmark uses `forceRefresh`, which keeps target order | Benchmark vs production differ |
| 11 | CAND-2 "`byIncomingTrip` hashed on every `isDominated`, `cannotEnter`" | The compact scan passes a cached peer mask. Hashing happens in the per-instance mask refresh (once per eligible alight), in `insert` / `remove`, and in the merge | Retargets CAND-2 |
| 12 | CAND-3 "≈855–880 suppressed as duplicates" | `duplicatesSuppressed` = valid − transfer representatives, so it also counts equivalent-transfer collapses. About 2,700 distinct journeys are still built and then filtered by an O(n²) envelope | Building only representatives saves ≤ 25 %. CAND-24 matters more |
| 13 | CAND-4 risk "must stay ≥ the true value" | For INV-1 the deadlines must be **equal**. A looser deadline admits more walking labels, which changes quota evictions | Changes CAND-4's acceptance check |
| 14 | CAND-5 gain | Snapshot load (866–916 ms) runs in parallel with graph preparation (513–640 ms), and endpoints need both. Persisting only the snapshot saves about 0.25–0.35 s, not 0.9 s | §6 |
| 15 | CAND-12 (a) "strip fields the app's decoders never read" | `LiveTransitService` reads `Notes` and passlists through the same models and the same static `DepartureBoardCache`. Trimming must be limited to routing requests with their own cache namespace | CAND-12 (a) |
| 16 | §12.6 date caveat | Confirmed: the installed-feed tests use 2026-10-08, which is outside generation 6 | Step 0 |
| 17 | INV-7 scope | Chunk count follows `ProcessInfo.activeProcessorCount` (§3.6) | CAND-23 |

---

## 3. Where the time goes

### 3.1 Critical path per sample

Times in ms from calculation start. Request times are aligned via the wave-1
request, accurate to about ±20 ms.

| Event | priming | warm | cold |
|---|---:|---:|---:|
| Discovery planning (`realtimeDiscovery`) | 1,228–1,435 | 104–520 | 1,118–1,217 |
| Discovery boards in flight (count) | 1,455–4,108 (24) | 512–2,283 (16) | 1,236–2,878 (24) |
| Warm-up scan (`walkingPreparation`) | 1,220–2,899 | 89–2,229 | 1,114–2,374 |
| Preliminary build ends | 3,262 | 2,748 | 2,718 |
| Speculative boards (2) | 3,280–4,059 | 2,838–3,310 | 2,746–3,041 |
| Live phase ends | 5,298 | 3,363 | 3,681 |
| Live phase end − last response | **1,189** | **54** | **640** |
| Critical branch | discovery → matching tail | warm-up → build → speculative fetch | discovery → matching tail |

After the live phase every sample runs the same serial chain: pass 1 →
build → wave 1 (one board) → pass 2 → build → wave 2 (11 ms) → assembly →
render.

Warm planning took 416 ms against its `min(250, budget/10)` bound. The bound is
checked only between steps, which likely explains why warm planned 16 boards
instead of 24. This makes discovery coverage depend on CPU load.

### 3.2 The second pass

- Wave 1's only request in every sample was `000200508016` (Héienhaff),
  `lines=6`. The speculative completion had requested `000200508016`
  `lines=16`. It was targeting a schedule-only pick that changes to line 16
  there; 29 → 16 is in the final list.
- Live data from discovery's Breedewues board showed bus 850 running 13 min
  late. That made 850 → 6 at Héienhaff the best journey.
- ATP passlists cover only the board stop and later stops: all 2,354
  departures start at the board stop. The line-6 boarding event at Héienhaff
  therefore needs a board at Héienhaff or upstream of it. The 16 Kirchberg
  boards cannot supply it.
- Discovery never queried Héienhaff (§3.5).
- `routingEffectChanged` triggered a full rescan. Its counters match pass 1
  exactly in rounds 1–3 (for example 4,279 / 822,551 / 5,398,404 alighting
  checks in cold) and differ by 4–7 retained labels in round 4.

### 3.3 Inside a pass

Cold sample, pass 1 = 1,148 ms:

| Part | ms | Notes |
|---|---:|---|
| Rounds 2+3 scan + merge | 640 | merge 341 ms, all serial |
| Rounds 1+4 | 52 | |
| Trip preparation | 16 | cached across rounds |
| Walking transfers | ≈ 260 | half of the 519 ms stage |
| Unattributed | ≈ 180 (167–391 across passes) | `BoardingIndex`, 3 × `walkingBoardingDeadlines`, patch overlay, candidate collection |

- **Merge stall.** `Raptor.search` (lines 146–205) merges every ready chunk in
  index order, and only then enqueues new chunks. At most 20 finished chunks
  can wait, so a slow early chunk blocks enqueueing altogether. The data that
  would size this effect (`summedChunkMilliseconds`, `slowestChunkMilliseconds`,
  `labelAttempts`, `rejectedBeforeAllocation`) exists in `RoutingRoundMetrics`,
  but the harness exports only five fields.
- **Round 3's 5.4 M alighting checks.** Each source label at a stop boards
  every later trip of every pattern through it, because different trips never
  dominate each other. Each feasible boarding then becomes a candidate at every
  eligible downstream stop. 634,807 (12 %) enter chunk profiles. Reducing the
  count exactly is not possible: dropping any label that would have entered a
  profile changes later evictions (INV-4 / EXP-3). So the levers are the cost
  per check and per insert, and taking the merge off the serial path.
- **`walkingBoardingDeadlines`** runs three times per scan. Each run covers all
  patterns × trips × days × stop times, about 1.3 M iterations, plus one
  dictionary lookup per trip and day. Estimated 10–15 ms per call; to be
  measured.

### 3.4 Candidate building (0.31–0.52 s, 3 times per search)

Each of the 3,600 candidates goes through normalisation, structural
validation, a full `Journey` build with two string keys, one to three uncached
`transferDecision` / `selectedTransferRule` calls per transfer, and publication
validation. About 2,700 representatives then enter `envelopeIDs`, which visits
every journey departing no earlier for each journey: about 3.6 M pair visits
over large `Journey` values. 26 survive.

### 3.5 The boards (474 KB median) and what the matcher reads

Measured on the 73 captured bodies: 2,354 departures (32 per board), 16.5
passlist stops per departure, 84 % with a live signal. The 16 % without one
are skipped by matching but still decoded.

| Part | Share | Read by routing? |
|---|---:|---|
| Passlist (`Stops`) | 87 % of departure bytes | partly |
| — `mainMast*`, `altId`, `hasMainMast` | ≈ 40 % of passlist bytes | no |
| — `dep/arr/rtDep/rtArrPlatform` objects | 13 % | no (engine reads `*Track`) |
| — `id` (always `A=…@L=…`, never equal to a GTFS ID; `extId` is present on all 38,871 stops) | 7.6 % | compared, never matches |
| — `lat`, `lon`, `minimumChangeDuration`, `entry`, `*TrackHidden`, `Notes` | ≈ 8 % | no |
| `ProductAtStop`, `Notes`, `mainMast*`, product `icon`/`operator*` etc. | ≈ 9 % of departure bytes | no |

- Routing reads: departure `JourneyDetailRef.ref`, product `line`, `lineId`,
  `name`, `catOutS`, `time`/`date`, `rt*`, `prognosisType`, `cancelled`,
  `reachable`, `direction`, `platform.text`, `rtPlatform.text`, `stopExtId`.
  Passlist: `name`, `extId`, `routeIdx`, times and dates, `rt*`, `*Track`,
  prognosis types, cancellation flags, boarding/alighting flags.
- Removing the unread fields and `id`: decoded 46.4 → 13.5 MB (−71 %), gzip
  4.46 → 0.76 MB (−83 %).
- Destination-side boards: 40 of 73 requests, 35.0 of 46.4 MB, median total
  1,491 ms. Origin-side boards: 24 requests, 8.1 MB, median 1,028 ms.

### 3.6 Client-side request time and determinism

Client-side time per request, measured as `taskInterval − (queue + server wait
+ transfer)`:

| Requests | priming | warm | cold |
|---|---|---|---|
| Discovery (CPU busy: warm-up, decode, bike, cold start) | 550–915 | 89–355 | 83–108 |
| Speculative | 26–50 | 65–85 | 3 |
| Wave 1 (CPU idle) | 1.2 | 2.9 | 1.4 |

The harness does not record `requestStart`, `requestEnd` or `responseEnd`
against the task end, so the phase cannot be located yet. Two hypotheses fit:
CPU starvation of the network stack by the warm-up's ten `.userInitiated`
workers and other work, or ATP / relay queuing under 24 concurrent requests.
Server wait was 164–630 ms for the speculative and wave-1 requests (one or two
at a time) and 197–1,898 ms within the discovery batch.

**Determinism.** Workers = `min(10, activeProcessorCount)` and chunk size =
⌈patterns / (workers × 12)⌉. Each chunk removes dominated labels and evicts
over quota before its survivors are re-inserted in chunk order. That is not the
same as one sequential insertion. Example: a label whose dominated peer was
evicted inside another chunk can now be rejected by `cannotEnter`. So results
can depend on core count: 10 on the benchmark Mac, 6 on an iPhone 17.
`ROUTING_VERIFY_KERNEL` compares two kernels that use the same chunking, so it
cannot detect this.

---

## 4. Options

### 4.1 Overview

| ID | Option | Class | Expected gain | Confidence |
|---|---|---|---|---|
| CAND-11 (ext) | Stop the merge stalling the scan, then shard the merge per stop | Exact | −0.25–0.45 s per pass | High for merge, medium for stall |
| CAND-2 (ext) | Cheaper profile insert/remove, flat instance data | Exact | −0.05–0.15 s per pass | Medium |
| CAND-1 (ext) | Session-wide transfer-decision cache + unscoped fast path | Exact | −0.02–0.08 s per pass, plus builds | Medium |
| CAND-21 | Walking-transfer bookkeeping without per-pair copies | Exact | −0.08–0.18 s per pass | Low–medium |
| CAND-4 (ext) | One feed pass for all deadline levels | Exact | −0.02–0.05 s per pass | Medium |
| CAND-22 | Build `BoardingIndex` per stop in parallel | Exact | −0.02–0.06 s per pass | Low |
| CAND-24 | Envelope with a scalar prefilter | Exact | −0.05–0.15 s per build | Medium |
| CAND-3 (corr) | Representative-first builds, compact keys | Exact | −0.05–0.12 s per build | Medium–low |
| CAND-25 | Matching memo scoped to the batch | Replay-exact | 0–0.3 s (cold, priming) | Medium |
| CAND-26 | Match boards as they arrive | Replay-exact | −0.4–0.6 s cold, −0.8–1.1 s priming, ~0 warm | Medium–high |
| CAND-27 | Fast discovery planning | Replay-exact* | −0.05–0.3 s; deterministic coverage | Medium |
| CAND-28 | Line filters at selected transfer stops cover connecting lines | Live | removes pass 2 here: −1.8–2.1 s today, −0.7–1.0 s after exact steps | Medium–high (≈ 70 %) for this route |
| CAND-29 | Transfer-first discovery ordering | Live | covers transfer stops; −0.3–0.8 s by dropping hub boards | Medium (≈ 60 %) |
| CAND-10 (ext) | Warm-up priority and worker count | Exact with CAND-23 | −0.3 to +0.5 s | Low |
| CAND-23 | Chunk count independent of cores | Exact on the 10-core Mac | determinism; frees worker count as a tuning knob | Medium (verify first) |
| CAND-30 | Locate the client-side request time | Diagnostic | up to −0.9 s priming, −0.1–0.35 s warm | Unknown |
| CAND-12 (a, ext) | Relay trims unread fields for routing only | Exact if scoped | −71 % decoded, −83 % gzip; latency ≤ 0.1–0.2 s | High for bytes, low for time |
| CAND-5 (corr) | Persist the routing snapshot | Exact | −0.25–0.35 s cold and priming | High |
| CAND-31 | Warm router and walking graph before the first search | Exact for results | −0.9–1.1 s on the first search, if the gate allows it | High; owner decides |
| CAND-14 | Start walking refinement after first render | Exact | −0.1–0.4 s priming render | Low–medium |
| CAND-32 | Run the bike branch at lower priority | Exact for transit | indirect | Low |
| CAND-33 | Harness and instrumentation | — | makes the above measurable | — |
| CAND-34 | Incremental pass-2 rescan | Exact (research) | up to −0.5 s if pass 2 stays | Low |

\* CAND-27 is identical whenever planning finishes inside today's 250 ms bound.
When it does not, today's output depends on CPU load.

### 4.2 Kernel (exact)

**CAND-11 (extended): stop the merge stalling the scan.**

- *Change.*
  - (a) Move `merge.append` out of the enqueue loop. Workers are re-filled as
    soon as a chunk finishes, and a merger task consumes chunks in index order.
  - (b) Shard the merge by stop. Each shard merges its stops in chunk order.
    IDs are `base + Σ labels of earlier chunks + Σ labels of this chunk at
    lower stops + slot`, which is what today's loop assigns.
  - (c) `materialize` per shard.
  - Keep memory bounded: release a chunk once every shard has consumed it.
- *Where:* `RaptorSearch.swift` (lines 146–212), `RaptorPatternMerge.swift`,
  `RaptorCompactScan.materialize`.
- *Gain:* the merge of rounds 2+3 (276–416 ms per pass) drops to about
  40–60 ms, and the stall goes away. Estimate −0.25–0.45 s per pass. The
  warm-up scan benefits too.
- *Risk:* ID and order mistakes (INV-7); memory if (a) buffers all chunks.
- *Verify:* `ROUTING_VERIFY_KERNEL=1`; extend `RaptorParallelMergeTests` with
  shard counts 1, 3 and 10 and out-of-order completion; check equivalence
  replay JSON for identical output; check `merge_ms` and wall time per round.

**CAND-2 (extended): profile bookkeeping.**

- *Change:*
  - Keep incoming-trip peer masks in a small inline array instead of a
    `[Int: UInt64]`.
  - Maintain quota membership incrementally instead of rebuilding five orders
    per insert once full.
  - Use fixed-capacity slot arrays.
  - Flatten `ActiveTripInstance` from seven heap arrays (`[Date?]` × 5,
    `[Bool]` × 2) into one contiguous scalar buffer, using `Double` seconds with
    NaN for missing.
  - Reuse a scratch buffer for the per-instance `alights` array.
- *Gain:* −0.05–0.15 s per pass (EXP-4: `consider` ≈ 40 % of busy CPU).
- *Risk:* tie-breaks must stay bit-identical (§2 rows 1–2).
- *Verify:* as CAND-11, plus `RaptorCompactProfileTests`.

**CAND-1 (extended): transfer decisions.**

- *Change:* a decision depends only on the snapshot and the preferences, not
  on live data.
  - Keep a decision cache per worker that survives chunks, rounds, passes and
    the warm-up.
  - Precompute the winning unscoped rule per `(from group, to group)`, and fall
    back to the full search only for the 213 scoped rules.
  - Use the same cache in `buildJourney`, `JourneyStructuralValidator` and
    `RaptorWalkingShortcut`, which call `transferDecision` /
    `selectedTransferRule` uncached up to three times per transfer.
- *Gain:* −0.02–0.08 s per pass, plus 10–40 ms per build.
- *Risk:* the earliest-row tie-break (§2 row 1).
- *Verify:* a test comparing the fast and full paths over every rule pair in
  the installed feed and a fixture; kernel and replay checks.

**CAND-21: walking-transfer bookkeeping.**

- *Change:* `relaxWalkingTransfers` builds one tuple per (eligible label ×
  target) and then copies a full `WalkingRoute` (polyline, steps, segments)
  into every work item, all serially. Instead, keep a route index in each item,
  pre-size per-target lists, and assign label IDs in the same global request
  order. Optionally build the per-target lists in parallel with prefix-sum IDs.
- *Gain:* −0.08–0.18 s per pass. Measure sub-spans first.
- *Risk:* ID order.
- *Verify:* the existing `verifyKernel` walking path; replay.

**CAND-4 (extended): boarding deadlines.**

- *Change:* compute the three remaining-ride levels in one feed pass per scan,
  with one patch lookup per trip and day. Optionally cache the scheduled part
  per session.
- *Gain:* −0.02–0.05 s per pass.
- *Risk:* deadlines must be equal, not just ≥ (§2 row 13).
- *Verify:* under `ROUTING_VERIFY_KERNEL`, assert the arrays equal the old
  per-round computation.

**CAND-22: per-pass overhead.**

- *Change:* build `BoardingIndex` per stop in parallel (sources, arrival
  order, prefix ranks).
- *Gain:* −0.02–0.06 s per pass.
- *Verify:* the existing `referencePrefixRanks` precondition.

**CAND-23: chunking independent of core count.**

- *Change:* compute chunk size from a constant 10 (and 1 when fewer than 32
  patterns are marked) rather than `activeProcessorCount`. The worker count
  stays `min(10, cores)`.
- *Effect:* identical results on the 10-core benchmark Mac. A 6-core phone
  then gets the Mac's results. Worker count becomes a pure scheduling knob,
  which CAND-10 needs.
- *Verify first:* run the equivalence queries with 1, 6 and 10 workers and diff
  the output. If they already match, drop this option.

### 4.3 Candidate building (exact)

**CAND-24: envelope prefilter.**

- *Change:* copy the scalars `envelopeIDs` compares (door departure, arrival,
  transfers, walking, accessibility, preferred flag, cancelled flag, tight
  flag) into contiguous arrays sorted by departure. Run the structural checks
  (`redundantAccessFeeder`, `redundantIntermediateTransfer`, `dominates`) only
  when the prefilter passes.
- *Gain:* −0.05–0.15 s per build.
- *Verify:* identical retained ID set; `JourneyQualityEnvelopeTests`.

**CAND-3 (corrected): representative-first builds.**

- *Change:* compute the signature as a compact value key instead of a string.
  Rank candidates per signature using values derived from the normalised
  candidate. Build fully in rank order until one passes validation.
- *Gain:* ≤ 25 % of builds, −0.05–0.12 s per build.
- *Risk:* `prefers` uses ranking fields of the built journey; derive them
  identically.
- *Verify:* identical journeys, IDs, order, `duplicatesSuppressed` and
  `invalidJourneys`.

### 4.4 Live data, replay-exact

**CAND-25: batch-scoped matching memo.**

- *Problem:* `patches(for:)` clears the memo on entry and in `defer`. The
  provider is an actor, so the speculative call clears discovery's memo while
  discovery is in flight. In cold and priming the calls overlapped and the
  tails were 640 and 1,189 ms. In warm they most likely did not (discovery's
  boards were all in 0.5 s before the speculative call), and the tail was
  54 ms.
- *Change:* count active batches and clear only when the last one ends, or
  pass the memo with the batch.
- *Gain:* 0–0.3 s. Its size is unknown, but EXP-5 shows how much this memo
  is worth.
- *Verify:* replay equality; `boardMatching` before and after.

**CAND-26: match while boards arrive.**

- *Problem:* matching waits for `boards(...)` to return every stop.
- *Change:* either
  - (a) match stop *i* once stops 0…*i* have arrived, keeping request order
    (which `matchedJourneys` reuse and patch merging depend on), or
  - (b) score each board in parallel as it arrives, then apply the
    order-dependent reuse and merge in one ordered pass.
- *Gain:* the 0.6–1.2 s tail shrinks to about the last board's matching
  (20–60 ms): −0.4–0.6 s cold, −0.8–1.1 s priming, about 0 warm.
- *Risk:* order dependence; the deadline paths.
- *Verify:* replay equality when the deadline does not bind; tail after the
  last response ≤ 150 ms.

**CAND-27: fast discovery planning.**

- *Change:*
  - Use stop-indexed arrays instead of the `[Int: Date]` lookup per stop time
    in `RealtimeReachability.advance`.
  - Compute remaining rides once per stop instead of calling `firstIndex`
    inside sort comparators.
  - Cache the walking-chain reachability for the session.
- *Gain:* −0.05–0.3 s. Warm would also plan the intended 24 boards instead of
  16, which costs network time but restores intended coverage.
- *Verify:* identical targets on replay when planning stays under 250 ms;
  planning time.

### 4.5 Live data, live changes (owner approval)

**CAND-28: connection-aware line filters at selected transfer stops.**

- *Change:* when completing a selected ride that boards at stop B after
  another ride, take the line filter at B from discovery's own rule
  (`realtimeTargets`): every named line with a qualifying departure whose
  later stops can reach the destination. Add those trips to `tripIDs`.
  Applies to both the speculative completion and the waves.
- *Gain (this route):* the speculative Héienhaff request would cover lines 6
  and 16, wave 1 would find nothing new, and pass 2 would not run.
  −1.8–2.1 s today, −0.7–1.0 s after the exact steps. ≈ 70 % sure for this
  route; generality unknown.
- *Risk:* slightly larger transfer-stop boards; more matching. Never fewer
  live checks (INV-6 holds).
- *Verify:* passes per search, `networkRequests`, `responseBytes`, coverage of
  shown journeys across ≥ 3 routes.
- *Offline result (2026-10-18, see the status section):* one pass in all 36
  replayed samples; the cost is two much wider boards (Luxexpo 2 → 33 lines on
  Thursday), about +14–17 % `responseBytes`. The live latency of those boards
  decides the net gain.

**CAND-29: transfer-first discovery ordering.**

- *Change:* keep the optimistic walking-chain envelope for deciding *which*
  stops qualify. Order them using the one-batch reachability that RAPTOR
  already caches: 1 remaining ride first, then 2, 3, and 0 (destination
  walkable) last. Ties break as today. A variant also caps zero-ride stops,
  for example at 4.
- *Gain:* discovery fetches transfer stops (Héienhaff, Luxexpo) instead of
  Kirchberg hubs. Discovery would end 0.3–0.8 s earlier, and the second pass
  would be avoided even when the live winner's transfer stop is not one the
  schedule picks used.
- *Risk:* reverses the deliberate ordering of `ac6945e`. Fewer boards for
  last-mile boardings near the destination.
- *Verify:* as CAND-28, plus a review of shown journeys on the four live
  scenarios.
- *Evidence (2026-10-20).* At 20:57 the second pass in every sample came from
  the Héienhaff P+R T1 board, which discovery had skipped. A replay with that
  one board added to discovery ran one pass, with identical results, about
  0.5 s faster (see the step 7 section). **But CAND-29 as specified would not
  fetch that board.** See the
  [offline evaluation](benchmarks/cand-29-offline-2026-10-20/README.md):
  - On the 20:57 capture, 269 of 317 first-wave candidates rank "1 ride", so
    the distance tie-break still decides. Each wave takes 8 boards, and
    Héienhaff P+R comes 102nd in wave 1 and 196th in wave 2. The zero-ride cap
    (`cap4`) picks the same 24 boards on all 7 captures.
  - The candidate cannot be replayed. On every capture, 12–16 of its 24
    discovery queries were never recorded, so every run stopped with
    `missing-replay-query`. These conclusions therefore come from the
    discovery plans, not from routing results.
  - Only 1 of the 7 captures has a second pass at all.
  - *Verdict:* not worth ATP requests in this form. Three directions remain
    untested, and each can be checked offline at plan level first:
    - a signal for transfer stops, such as the number of distinct departing
      lines;
    - the transfer stops of the preliminary journeys;
    - a few of the 24 slots reserved for such stops.

**CAND-10 (extended): warm-up scan.** With CAND-23 in place, give the warm-up
`.utility` priority or `cores − 2` workers. This is exact for its output and
frees CPU for networking, decoding and matching. Warm-up length matters only
where it is the critical path (warm), so measure both directions. Removing the
warm-up altogether (the original CAND-10) is a live change; re-test it only
after CAND-28/29 show that discovery covers the picks' transfer stops.

**CAND-30: client-side request time.**

- Record all `URLSessionTaskTransactionMetrics` timestamps and the task end.
- Add a relay `Server-Timing` header for the upstream ATP fetch. The body is
  unchanged.
- In one approved live session, alternate warm-up priority.
- Then either reduce contention (CAND-10/23/32) or order the most valuable
  boards first (CAND-29).

**CAND-12 (a, extended): relay trimming.** Measured: −71 % decoded, −83 % gzip.

- Requirements:
  - Opt-in per request: a distinct URL parameter, which also gives a distinct
    `BoardCacheScope` namespace, so the UI never receives trimmed boards.
  - Check the Worker's CPU limit for parsing 2 MB of JSON.
  - Check ATP terms.
- *Verify offline:* trim the captured bodies with the same rule and replay;
  results must be identical.
- *Value:* mostly CPU and memory, which helps phones more than the simulator.

### 4.6 Cold start, render, contention

- **CAND-5 (corrected):** a versioned binary snapshot. −0.25–0.35 s; graph
  preparation becomes the limit. Verify with a snapshot equality test.
  *Implemented (engine `83ecb6b`, pushed), measured −0.17 to −0.2 s on the simulator; see
  "CAND-5, persisted routing snapshot".*
- **CAND-31:** warm the router and walking graph when the app becomes active
  or the planner opens. Results are identical. The harness starts searching
  right after launch, so this shows up only if the gate definition changes.
- **CAND-14:** as in the brief. Priming's 649 ms render overlapped 816 ms and
  473 ms of refinement.
- **CAND-32:** `bikeCalculation` took 1.6 s alongside discovery in priming.
  Lower its priority. Check that publication does not wait on it once the
  transit path is faster: today the bike result is ready at 2.5 s and
  publication happens at 9.4 s.

### 4.7 Measurement (CAND-33)

1. Export every `RoutingRoundMetrics` field, and the warm-up's rounds, which
   are not recorded today.
2. Add sub-spans:
   - `BoardingIndex`, deadlines, patch overlay, candidate collection;
   - walking: request building / cache / work building / apply;
   - `buildJourneys`: normalise / structural / build / publication / dedupe /
     transfer groups / envelope / intermediate stops;
   - provider: fetch / `prepareBoard` / per-stop matching / session merge.
3. Copy the 73 baseline bodies out of the simulator's `tmp` before they are
   purged (about 46 MB; outside git) and rebuild a replay capture. This avoids
   a new live capture for all exact work.
4. Add a union capture for live A/B: one capture holding both arms' queries,
   topped up on replay misses. Live heuristics can then be compared offline.
5. `BenchmarkNetworkRecorder.didReceive` writes each body atomically and
   flushes stdout inside the measured fetch, before decoding. Move this off
   the path or report it as harness overhead. Production does not do it.

### 4.8 Research

**CAND-34: incremental pass 2.** Pass 2 repeats pass 1's counters in rounds
1–3. A delta rescan (rescan only chunks whose patterns or input labels
changed, and reuse merged profiles) could be exact, but IDs shift and retaining
chunk outputs costs about 130–150 MB in round 3. Pursue only if CAND-28/29
leave pass 2 common.

---

## 5. Ordered plan

Engine steps follow the brief's process: commit in MobilitéitKit → push →
update the pin, or point the app at the local package for measurement. Use one
small commit per option. All app replay comparisons alternate A/B runs (at
least 5 per arm) and compare medians (EXP-6 noise is 10–20 %).

| Step | Contents | Acceptance |
|---|---|---|
| 0. Evidence and instrumentation (no behaviour change) | CAND-33; update installed-feed test dates to generation 6 (separate commit); CAND-23 core-count test; rebuild a replay capture from the saved bodies | Replay reproduces the 6 engine journeys and the recommendation for all three samples; new metrics present; output identical to the pre-change build |
| 1. Provider, replay-exact | CAND-25, CAND-26 | Replay identical; live-phase end − last response ≤ 150 ms in cold and priming replays; realtime tests pass serially |
| 2. Merge | CAND-11 (a), then (b) | `ROUTING_VERIFY_KERNEL=1 swift test --no-parallel` passes; `InstalledEquivalenceReplayTests` JSON identical; replay identical; rounds 2+3 merge ≤ 120 ms per pass; cold pass 1 ≤ 0.9 s |
| 3. Remaining kernel | CAND-1, CAND-2, CAND-21, CAND-4, CAND-22, each verified alone | Same equality checks; pass ≤ 0.65 s; warm-up ≤ 1.1 s |
| 4. Candidates and planning | CAND-24, CAND-3, CAND-27 | Identical journeys, IDs, order and counters; `candidateBuilding` ≤ 0.2 s per build; identical discovery targets when planning < 250 ms |
| Checkpoint A (replay, no ATP) | — | Expected about 4.5 s warm, 5.4 s cold, 7.2 s priming. The gate still fails here; that is expected |
| 5. Live, owner approval | CAND-28; then CAND-29 | Across ≥ 3 routes, alternating A/B: one authoritative pass in most runs (target ≥ 2/3); `networkRequests` ≤ +20 %; `responseBytes` not higher; every shown ride has a fresh or attempted live board (INV-6); live coverage of shown journeys not lower; journey sets compared and reviewed for quality; no validator rejections |
| 6. Contention, cold start, render, payload | CAND-30 → CAND-10/23/32 decisions; CAND-5 (and CAND-31 if approved); CAND-14; CAND-12 (a) | Exact items: equality checks. CAND-12 (a): replay of trimmed captures identical. Cold `snapshotPreparation` ≤ 300 ms |
| 7. Re-baseline | Live priming, warm and cold × 3 each; device run with recorded boards (`Scripts/benchmark_routes_device.py`) | Every operation < 5,000 ms. Warm and cold: medians ≤ 4,000 ms, maximum ≤ 4,500 ms. Device timings reported |

---

## 6. Projection model

Per sample, the critical path is: setup + live phase + pass 1 + build + wave 1
+ [pass 2 + build] + wave 2 + assembly + render. These rows sum to the baseline
totals within rounding. The live phase is the later of two branches: discovery
plus its matching tail, or warm-up plus preliminary build plus speculative
fetch.

Assumptions:

| Parameter | Central | Range |
|---|---|---|
| Pass time multiplier | × 0.5 | 0.35–0.65 |
| Build time multiplier | × 0.55 | 0.4–0.7 |
| Warm-up multiplier | × 0.5 | 0.35–0.65 |
| Matching tail after the last response | ≈ 100 ms | 50 ms to half of today's |
| Wave without new boards | ≈ 20 ms | — |
| Discovery request timings | unchanged unless stated | CAND-29 removes 0.3 s in the central case |

The results are the table in the Summary. Simulator on an M4 with 10 cores.
A 6-core iPhone will be slower on the CPU-bound parts, so step 7 includes a
device run.

---

## 7. Decisions for the owner

1. **ATP budget.** Live searches cost about 19–27 requests each:

   | Run | Searches | ≈ Requests |
   |---|---|---:|
   | (a) Instrumented re-baseline for CAND-30 | 5 | ≈ 125 |
   | (b) CAND-28/29 A/B, 3 routes × 2 arms × 3 | 18 | ≈ 450; or ≈ 120 for three union captures plus offline replay |
   | (c) Final re-baseline | 9 | ≈ 225 |

   Steps 0–4 need no ATP if the saved bodies can be replayed.
2. **Live behaviour.** CAND-28. CAND-29, which reverses the deliberate
   discovery ordering kept in `ac6945e`. Removing the warm-up (CAND-10).
3. **Relay changes** (`verkeier-relay`): a `Server-Timing` header (diagnostic
   only); routing-only field trimming (Worker CPU limits, ATP terms).
4. **CAND-23** changes on-device results so they match the simulator. Exact
   on the benchmark Mac.
5. **Gate definition.**
   - Should priming include building the snapshot and graph when nothing
     warms them earlier (CAND-31)?
   - Simulator only, or device as well?
   - Is "replay-exact" acceptable as INV-1 evidence for provider changes, where
     results can only differ if a deadline binds?
6. **Margin target.** This plan assumes ≤ 4,000 ms medians.

No option here shrinks an INV-6 budget: 8 s acquisition, ≤ 3 transfers,
48 labels, 2 h → 24 h window, and live checks on every selected vehicle.

---

## 8. Considered and not recommended

| Idea | Why not |
|---|---|
| Time-based label pruning in round 3 | Not exact: removing labels changes quota evictions (INV-4, EXP-3) |
| Fewer, larger chunks to cut merge input | Changes results (§3.6). Revisit only after CAND-23, with new hashes approved |
| Narrower board windows or less rounding | Changes live coverage (CAND-12 b); small payoff, because server wait dominates |
| Trimming passlists to downstream stops | Already the case: ATP passlists start at the board stop |
| Relay caching of boards | ATP terms (CAND-7 a); no benchmark gain under `forceRefresh` |
| Rescanning only when the top 6 would change | Cannot be proved without the rescan |

---

## Appendix A — Boards fetched

Discovery boards are listed in request order. Priming and cold fetched all 24;
warm fetched the first 16.

| Group | Stops (distance) |
|---|---|
| Discovery 1–8 (access stops) | Senningerberg Gromscheed, Breedewues, Kapell, Charlys Statioun, Rue des Résidences; Hostert Kierfecht, Stade Jos Becker, Binnewee (272–600 m from origin) |
| Discovery 9–16 | Kirchberg Simone de Beauvoir, Luxexpo Entrée Sud, Poutty Stein, Mathias Tresch; Neudorf Kapell; Dommeldange Dauschbuer; Weimerskirch Biechelchen; Cents Charles de Tornaco (567–1,249 m from destination) |
| Discovery 17–24 | Kirchberg Konrad Adenauer (the destination stop), prov. Konrad Adenauer, Coudenhove-Kalergi, Avalon, Albert Borschette, Universitéit, Mischekopp, Sichegronn (0–499 m from destination) |
| Speculative | Kirchberg Gare routière Luxexpo (lines 21, 6); Senningerberg Héienhaff (line 16) |
| Wave 1 | Senningerberg Héienhaff (line 6). The stop serves lines 16, 223, 29, 361, 6 and 850 |
