# Steps 5 and 6 of the routing speed plan, completed (Thursday 29 October 2026)

On 29 October the owner handed over the remaining decisions: "Make decisions for yourself. Complete 5 and 6 on
your own." This folder records what was decided for each open item of steps 5 and 6 in
[ROUTING_SPEED_PLAN.md](../../ROUTING_SPEED_PLAN.md) §5, and the evidence behind each decision.

| Item | Step | Decision | Evidence |
|---|---|---|---|
| CAND-23 chunk count independent of cores | 6 | **Adopted**, engine `1d0ce96` | Exact by construction on the 10-core Mac; installed-feed JSON identical |
| CAND-28b split wide line filters | 5 | **Adopted**, engine `a152c0f` | Live A/B (279 ATP requests) and replays of 14 captures, below |
| CAND-29 transfer-first discovery | 5 | Closed | Pass 2 in 1 of 8 captures; as specified it misses that board (20 Oct evaluation) |
| CAND-10 warm-up priority or worker count | 6 | Declined | Replays: −26 ms and −2 ms median, signs flip by capture |
| CAND-14 refinement after first render | 6 | Declined | Replays: render −14 ms median, total +13 ms |
| CAND-32 bike branch priority | 6 | Declined | Bike work ends 9–217 ms into a search; publication starts after 2.0 s |
| CAND-31 warm before the first search | 6 | Declined | Priming's snapshot and graph cost 50–175 ms in all |
| CAND-12 (a) relay trimming, live | 6 | Not deployed | Offline: identical results, no total change; see its own write-up |
| CAND-30 client-side request time | 6 | Closed earlier | 18 Oct: machine load, no code change |
| CAND-5 routing snapshot | 6 | Done earlier | Cold `snapshotPreparation` 21–25 ms here (acceptance: ≤ 300 ms) |

- **Code:** MobilitéitKit `1d0ce96` (CAND-23) and `a152c0f` (CAND-28b), pushed to `origin/main`. The app pins
  `a152c0f`.
- **ATP requests:** 279, all in the live A/B at 18:20–18:32 on mains power. One extra attempt at 18:06 sent no
  request to ATP: Cloudflare refused my script with error 1010 (browser signature) before the Worker ran. That
  rule protects the relay, so I didn't work around it. The mechanism was measured through the app instead.
- **Machine:** MacBook Air M4 with the iPhone 17 simulator, on mains power, Low Power Mode off. Replays waited for a
  1-minute load below 6; CPU canary 1.86–2.70 s, median 2.05 s.
- **Builds:** Release simulator builds made with `ENABLE_CODE_COVERAGE=NO`, from `git archive` of app `c9dea17`
  plus the walking graph files, each pointed at a local engine copy ([`tools/make_arm.py`](tools/make_arm.py)).
  Arm A: engine `1d0ce96`. Arm B: arm A plus the split. Arm C: arm A plus the step 6 switches
  ([`tools/apply_knobs.py`](tools/apply_knobs.py)), which were never committed.

## CAND-23: chunking independent of the core count

The scan's chunk size came from the worker count, which is `min(10, cores)`. Each chunk evicts labels before the
merge, so a 6-core phone could in principle retain different labels than the 10-core Mac. Chunks are now sized
from `Raptor.maximumPatternWorkers` (10) whenever the scan is parallel. The worker count only schedules.

- **Exact on the benchmark Mac:** the installed-feed equivalence JSON (18 pages) is byte-identical to `1bd2ebf`.
- **Worker counts:** 1, 6 and 10 workers give identical pages. The installed worker-count test now fails on any
  difference instead of warning.
- **Tests:** `ROUTING_VERIFY_KERNEL=1 swift test --no-parallel`, 348 tests pass.
- The 16 October check had already found no difference on these queries, so this is a guarantee rather than a
  change anyone will see.

## CAND-28b: split wide line filters into parallel requests

### Why

CAND-28 asks transfer-stop boards for every line that can still reach the destination. At Luxexpo
(`000200417050`) that is 28–33 lines and 2.2–3.1 MB decoded, about five times the median board.

- **It was the last board to arrive in 12 of 19 live samples** across the 19–22 October captures, by 105–899 ms
  over the next board ([`results/last-board-per-sample.txt`](results/last-board-per-sample.txt)).
- **ATP's wait grows with what a board returns.** Across 9 captures, the correlation of ATP's wait with decoded
  size is r = 0.18–0.54, about 240–390 ms per MB or 4–10 ms per departure
  ([`results/board-wait-vs-size.txt`](results/board-wait-vs-size.txt)). The relationship is weakest in the slow
  rounds, when every board is slow.
- Narrowing the filter would risk INV-6, because a dropped line could carry a shown ride. Splitting keeps every
  line. The parts return the same rows that one request returns.

### What changed (`a152c0f`)

- A filter above 12 lines is dealt round-robin into parallel requests: 33 lines become 11 + 11 + 11 and 13 lines
  become 7 + 6. The parts' rows are combined into the stop's one board, as cached partial coverage already was.
- **Each extra part needs a free permit** of the provider's board-request capacity, taken without queueing
  (`RealtimeBoardRequestScheduler.takeFreePermits`). Free permits mean nothing waits, so a split never delays
  another board's start. Without spare capacity the filter stays one request, as before.
- Every other filter, and every unfiltered board, is unchanged.
- **Tests:** a new provider test checks the parts, their concurrency and the permit accounting for capacities 1,
  2, 3 and 8. `RealtimeStopBoardCoverageTests` now expects two parts for its 17-line case. The full suite passes:
  349 tests, serial, with kernel verification.

### Live A/B (18:20–18:32, 279 requests)

ATP was slow during the whole round: other boards took a median of 0.85–1.8 s, against 0.5 s on 22 October. Arm A
is `1d0ce96`, arm B is `a152c0f`'s split on top. The runs alternated A, B, B, A on `live-now` and A, B on
`live-reverse` ([`tools/live_ab.sh`](tools/live_ab.sh)). Each row is one sample; network time is server wait
plus transfer.

| Run | Arm | Sample | Total, ms | Realtime stage, ms | Passes | Requests | Other boards, median ms | Luxexpo, ms | Luxexpo / others | Realtime / others |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 `live-now` | A | priming | 5,280 | 3,445 | 1 | 26 | 1,460 | 2,433 | 1.67 | 2.36 |
| 1 `live-now` | A | warm | 4,204 | 3,578 | 1 | 26 | 1,795 | 1,754 | 0.98 | 1.99 |
| 1 `live-now` | A | cold | 3,755 | 2,877 | 1 | 26 | 1,544 | 2,142 | 1.39 | 1.86 |
| 2 `live-now` | B | priming | 5,366 | 4,058 | 2 | 31 | 1,646 | 2,128 | 1.29 | 2.47 |
| 2 `live-now` | B | warm | 2,361 | 1,854 | 1 | 29 | 1,026 | 1,371 | 1.34 | 1.81 |
| 2 `live-now` | B | cold | 3,315 | 2,650 | 1 | 29 | 1,481 | 2,034 | 1.37 | 1.79 |
| 3 `live-now` | B | priming | 4,324 | 3,483 | 1 | 29 | 1,744 | 2,155 | 1.24 | 2.00 |
| 4 `live-now` | A | priming | 3,673 | 2,712 | 1 | 26 | 1,027 | 2,042 | 1.99 | 2.64 |
| 5 `live-reverse` | A | priming | 4,221 | 3,348 | 1 | 27 | 1,294 | 2,734 | 2.11 | 2.59 |
| 6 `live-reverse` | B | priming | 2,702 | 2,044 | 1 | 30 | 854 | 1,421 | 1.66 | 2.39 |

For arm B, "Luxexpo" is the slowest of its three parts.

- **The split board arrives sooner relative to the rest.** Luxexpo took a median of 1.34× the sample's other
  boards (1.24–1.66) with the split, against 1.67× (0.98–2.11) without it.
- **The realtime stage, in units of the sample's median board,** fell from a median of 2.36 to 2.00.
- **Estimated saving:** if each arm A sample's Luxexpo board had taken 1.38× the other boards, the last board
  would have arrived 418, 0, 11, 626 and 387 ms earlier. That is about −0.3 s on average when Luxexpo arrives last
  by a margin, and nothing when it doesn't. ATP's state changes within minutes, so raw totals of one arm against
  the other say little here.
- **Cost:** 3 more requests per search (Luxexpo +2, the 13-line Kirchberg board `000200417039` +1), +11.5 %.
  Bytes are unchanged in one-pass samples: 18.84–18.92 MB against 18.96–18.97 MB on `live-now`.
- **Gate:** it still fails in this slow period, as decision A expected. 1 of 5 samples per arm went over 5 s. The B
  sample over 5 s is the one with two passes.

**The second pass in B's priming sample is not the split's doing.** That sample's wave 1 took a different board
set (`000200508011`, `000200508016`) than either replay of the same capture, and its pass 1 started 0.4 s later.
Both arms replay that capture with one pass.

### Same data, same results

Each arm replayed each capture with recorded latency, with no ATP request
([`tools/replay_batch.sh`](tools/replay_batch.sh), [`tools/compare_arms.py`](tools/compare_arms.py)). An arm that
asks for a query the capture never recorded gets it assembled from recorded rows of the same stop and window
(`--replay-approximate`). On the older captures that means arm B's parts, built from the recorded wide board.
On today's B captures it means arm A's wide board, built from B's parts.

| Captures | Sample pairs | Journeys, options, coverage | Other differences |
|---|---:|---|---|
| 8 older captures (19–22 Oct) | 18 | identical in all 18 | `predictedEvents` −1 to −16 in 4; `boardCacheHits` +3 in 1 |
| Today's 6 live captures | 10 | identical in all 10 | recommendation in 2; board arrival order in 3; `boardCacheHits` +2 in 2; `predictedEvents` −2 in 1 |

- **The recommendation follows the wall clock, not the split.** On capture L2B, arm B's replay of its own capture
  didn't reproduce its own live recommendation. Twelve minutes later both arms recommended a third option, and
  one arm A repeat recommended the vel'OH! option. The engine's journeys were identical in every repeat.
- **`predictedEvents` and `delayedPastBoardings` move by one or two** in some arm B samples. Parts arrive in a
  varying order, which settles equal-rank rows in a different order (see "Round-3 +4 counters" in the plan).
  `s7-L2` varies by up to 17 between replays of unchanged bodies.
- **`boardCacheHits` counts one hit per reused part**, so a split board that a later window reuses counts 2–3
  hits where the wide board counted 1.
- Replay totals in approximate mode aren't comparable. The harness builds each part from the 2–3 MB wide body
  inside the app process.

## Step 6 switches (replays, no ATP)

Arm C read three switches at run time (unset: arm A's behaviour):
- `ROUTING_EXPERIMENT_WARMUP=utility`: the warm-up scan's tasks at `.utility` instead of `.userInitiated`;
- `ROUTING_EXPERIMENT_WARMUP=workers8`: the warm-up scan on 8 workers. This is exact only because CAND-23 is in;
- `ROUTING_EXPERIMENT_DEFER_REFINEMENT=1`: walking refinement starts after the first render.

The replays covered 4 captures (`s7-L1`, `st22-L2`, `st-L1` with its second pass, `c28-now`). Each variant ran 2
repetitions, in forward then reverse order. The table gives median changes against the unset build over 10
capture-and-sample cells ([`results/knobs.json`](results/knobs.json)).

| Switch | Total | Realtime stage | Warm-up | First render | Results |
|---|---:|---:|---:|---:|---|
| `utility` (CAND-10) | −26 ms | −6 ms | −11 ms | −3 ms | identical |
| `workers8` (CAND-10) | −2 ms | +3 ms | +2 ms | 0 ms | identical |
| defer refinement (CAND-14) | +13 ms | 0 ms | +1 ms | −14 ms | identical |

- **CAND-10: declined.** `utility` helps `st22-L2` (−81 to −216 ms) and `c28-now` (−122 ms) but costs `s7-L1`
  +129 to +141 ms. Replay noise is 10–20 %. On the 10-core Mac the warm-up doesn't starve the critical path. A
  6-core phone wasn't measured.
- **CAND-14: declined.** The first render takes a median of 67 ms (43–237), and refinement overlaps 44 ms of it. At
  most about 35 ms could be saved, and the replays found 14 ms.
- One cell shows a "≠": `s7-L1`'s warm sample, against the base's second repetition. There the base differed from
  its own first repetition in board arrival order only.

## Decided from existing data

- **CAND-32, bike branch priority: declined.** `bikeCalculation` takes 8–96 ms and ends 9–217 ms after a search
  starts. Publication starts 2.0–7.4 s in, so nothing waits on the bike branch. The plan's 1.6 s came from the
  CPU-inflated baseline.
- **CAND-31, warming before the first search: declined.** Since CAND-5, priming's `snapshotPreparation` is
  20–115 ms and `graphPreparation` 30–58 ms, 50–175 ms together. Warming would save about 0.1 s on the first search after launch, but
  it would cost work on every activation, most of which never search. The gate doesn't need it either.
- **CAND-29: closed.** Since CAND-28, only 1 of 8 captures runs a second pass (20 October, 20:57). CAND-29 as
  specified doesn't fetch that board.
  - Of the three untested directions, "the transfer stops of the preliminary journeys" is what speculative
    completion already requests.
  - The other two add discovery boards for a case that occurs in about 1 search in 8.
- **CAND-12 (a) live: not deployed.** The [offline check](../cand-12a-offline-2026-10-29/README.md) found identical
  results, but no measurable total change on the simulator. The Worker would have to buffer every body, and
  today's slow round showed relay plus network at a median of 0–48 ms per sample. ATP's terms are also unchecked.
  A phone on a slow mobile connection is the case where it could pay; that would need a device measurement first.

## Files

| File | Content |
|---|---|
| `tools/make_arm.py`, `tools/build_arms.sh` | Arm source trees from `git archive`, with a local engine package; Release builds |
| `tools/apply_knobs.py` | Arm C's experiment switches (scratch only) |
| `tools/live_ab.sh`, `tools/live_report.py`, `tools/live_table.py` | The live A/B and its per-sample table |
| `tools/boards.py`, `tools/lastboard.py` | Board width, size and timing per request; last board per sample |
| `tools/replay_batch.sh`, `tools/replay.sh`, `tools/compare_arms.py`, `tools/knob_report.py` | Replays and their comparisons |
| `tools/split_experiment.py` | The direct relay experiment Cloudflare refused (error 1010); kept for the record |
| `results/live-ab-table.md`, `results/live-ab-summary.txt` | The live A/B |
| `results/last-board-per-sample.txt`, `results/board-wait-vs-size.txt` | Board timing across the 19–22 October captures |
| `results/compare-split-old.json`, `results/compare-split-live.json` | Arm A against arm B on the same data |
| `results/knobs.json` | The step 6 switch replays |

The scripts' paths point to this session's scratch folder. The live captures and the replay runs (without
transfer-walk stores) are in `~/Developer/Verkeier-captures/cand-28b-live-2026-10-29/`, outside git.
