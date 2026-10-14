# Stored transfer walks: benchmark and equivalence evidence (14 October 2026)

Three arms, same installed data, same fixed planning times, recorded ATP transport (no network):

| Arm | Build |
|---|---|
| A | `main@30fc1fc`, no stored walks |
| B | `feature/transfer-walk-table` with stored walks **off** (`ROUTING_TRANSFER_WALKS=0`) |
| C | `feature/transfer-walk-table` with stored walks **on**, table built once beforehand in its own process |

Release simulator builds (iPhone 17, iOS 27, `ENABLE_CODE_COVERAGE=NO`), Apple M4 MacBook Air, installed GTFS generation 5 and walking graph `20260921`,
`--full-evidence` (complete canonical plans). Planning times 2026-10-15 08:00 (departure scenarios) and 09:00 (arrive-by), both inside the installed
timetable. Per scenario: one warm run (priming + 1 warm sample) and two fresh processes. All 96 operations completed; plan exports are in
`samples-digest.json` (SHA-256 of each canonical plan, not the 16 MB raw plans). Commands: `Scripts/benchmark_routes.py --transfer-walks on|off`
with `--time`, `--warm 1 --cold 2 --full-evidence --maximum-limit-ms 0`.

## Are the results identical?

**Yes, with one pre-existing exception that the table does not cause.**

- Every field the comparer checks (recommended option, option IDs, journeys, displayed legs, realtime coverage, rejections, paging flags, supplemental
  options) matched in **every** scenario, in all three comparisons (`compare-*.json`).
- `canonicalPlans` (complete plans with every walking polyline and distance) matched bit for bit in `depart`, `reverse`, `coordinates`, `exact`,
  `arrive` and `refresh` across all arms and samples.
- `rural` (and, between samples, `paging`) differ in exactly one numeric leaf: the **distance of the Pafendall funicular ride** (about 225.5 m),
  by 0.00 to 0.03 m. The only differing leaves are `...legs[n].distanceMeters` of legs with `mode: funicular`; with that one value masked,
  `canonicalPlans` are identical across all arms for every scenario and sample (`canonicalPlansMaskedFunicularSHA256`).

**Why the funicular distance moves, and why it is not the table.** The ride length is the sum of `CLLocation.distance` over a fixed 9-point track
(`PafendallFunicularConnection`). Measured in the iOS simulator process: before any native Valhalla routing it is 225.52731491656198 m on every call and every
thread; after native routing has run, the same call on the same coordinates returns 225.5485 m. The value therefore depends on process history. The
**unmodified baseline varies against itself**: arm A produced two different canonical plans among its own four `rural` samples and two among its four `paging` samples
(arm B: `paging` 2, arm C: `paging` 2, `rural` 1). Funicular pairs are never stored in the table and are computed live in every arm. With the table
on there is far less native routing in the process, which is why arm C happened to show the pristine value in all four `rural` samples.
This is recorded as a separate follow-up; it was left unchanged here because making it deterministic would change baseline output by centimetres.

## Exhaustive check on the real feed

`TransferWalkRealFeedEquivalenceTests` (needs `TEST_RUNNER_ROUTING_TEST_FEED_DIR`): all **11,188** directed transfer pairs of the installed timetable, table vs live.

- 11,182 table-served pairs: **bit-identical** (0 differences).
- 6 Pafendall funicular pairs (never stored, computed live on both sides): identical except the ride distance, which differs by 0.01 to 0.02 m
  (same effect as above): durations, polylines, labels and segment structure are equal.

## Speed

Median rendered total, milliseconds, per scenario (fresh process n=2, warm n=1; priming runs in `samples-digest.json`):

| Scenario | main (ms) | stored walks off (ms) | stored walks on (ms) | on vs main |
|---|---:|---:|---:|---:|
| **fresh process** | | | | |
| depart | 8,920 | 6,612 | 2,835 | -68% |
| reverse | 7,840 | 5,321 | 2,609 | -67% |
| coordinates | 5,588 | 5,502 | 2,772 | -50% |
| exact | 10,951 | 5,944 | 1,908 | -83% |
| rural | 4,583 | 4,553 | 1,952 | -57% |
| arrive | 9,453 | 9,544 | 6,126 | -35% |
| paging | 1,274 | 1,193 | 1,038 | -18% |
| refresh | 1,219 | 1,289 | 1,071 | -12% |
| **warm** | | | | |
| depart | 3,432 | 2,033 | 1,752 | -49% |
| reverse | 3,080 | 1,957 | 1,810 | -41% |
| coordinates | 2,513 | 1,828 | 1,735 | -31% |
| exact | 5,876 | 1,169 | 1,128 | -81% |
| rural | 1,264 | 1,289 | 1,213 | -4% |
| arrive | 5,390 | 6,795 | 6,292 | +17% |
| paging | 1,219 | 1,298 | 1,009 | -17% |
| refresh | 1,115 | 1,127 | 1,045 | -6% |

The table is built once per walking graph/timetable: **5.5-6.7 s** for 11,188 pairs (4,928-6,023 ms of building, 6.2 MB, 477 pairs without a route) on this machine
(`optimisation-*-run.json`). That is the one-time cost behind the launch screen; the simulator is not a phone, so expect it to be longer on an iPhone.

### Reading the numbers honestly

- Small samples (n=2 fresh, n=1 warm) from one session; fresh-process results are the meaningful column, warm differences of a few percent are noise.
  Arm A contains a 20.3 s outlier (`exact`, priming).
- The win is large where walking dominates (fresh process: -50% to -83% in departure scenarios). Arrive-by (-35% fresh, no gain warm) and paging/refresh are dominated by
  other work and improve little, and the single warm `arrive` sample was slower with the table (6.3 s vs 5.4 s) within what looks like run-to-run noise.
- Recorded transport answers instantly. Live ATP acquisition, which the earlier benchmarks showed was the other half of live search latency, is not measured here, so
  this is not a live-search result.
- Simulator, not a physical device.

## Live ATP check (run later the same day)

Re-run because network conditions may have changed. Simulator, live ATP, departure "now" (Gromscheed → Konrad Adenauer), one interleaved pass per arm
(`main` first, then the branch with stored walks on; the branch build is HEAD `26edc99`). One sample per cell, so treat these as indicative.

| Search | Before (`main`, ms) | After (branch, ms) | Change |
|---|---:|---:|---:|
| Fresh process (cold) | 8,314 | 4,467 | −46% |
| First search after launch (priming) | 7,601 | 5,712 | −25% |
| Warm (same process) | 3,569 | 3,657 | +2% (noise) |

The warm search gains nothing because the in-memory walk cache already holds those walks. The stored table helps a cold process start.

**Identical inputs.** Live responses differ between runs (predicted events 3,538 vs 3,507), so the live pair cannot prove identity. The combined live captures
of both runs were replayed through both builds with the same bike snapshot and planning time (no ATP requests). On identical data every route field matched,
including canonical plans, journeys, displayed legs and realtime coverage. The one difference is `matchingRejections` (52 vs 53 predictions outside a board's
time window) in the cold priming search, where the baseline's realtime acquisition took 3.9 s against 1.2 s on the branch, so the windows fell differently.
Replay timings: priming 6,605 → 3,912 ms; warm 3,435 → 2,985 ms.

**Attempts.** The first "before" attempt stopped on an ATP HTTP 503 (`provider-error-503`) and was rerun. The first "after" attempt stopped on this
harness's request budget during arrive-by, which costs about 68 requests per search. Arrive-by was dropped from this pass. Each live run recorded 87–89 ATP
responses. Raw captures (about 100 MB of third-party responses) are not committed; `samples-digest.json` holds timings and plan hashes, and
`replay/compare-identical-capture.json` holds the comparison.
