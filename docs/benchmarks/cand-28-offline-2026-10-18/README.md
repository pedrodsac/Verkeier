# CAND-28, offline evaluation (18 October 2026)

CAND-28 of [ROUTING_SPEED_PLAN.md](../../ROUTING_SPEED_PLAN.md) evaluated with recorded boards only. **No ATP
request was sent.** Every number comes from latency replays (`--replay-latency`) of the Thursday baseline
capture and the three Sunday captures, on the iPhone 17 simulator.

## What was changed

MobilitéitKit `1779b82` + the CAND-28 files (not committed; patch in the session notes):

- `JourneyPlanningSession+ItineraryRealtime.swift`: a selected ride that boards after another ride (a walk
  in between is fine, an in-seat continuation is not a transfer) is requested with its own line **plus every
  line discovery's rule names at that stop**, and the trips of those lines are added to `tripIDs`. Applies to
  the speculative completion and to the waves. Windows, stops and the first ride's board are unchanged.
- `JourneyPlanningSession+ConnectionLines.swift` (new): `connectionLines` runs `realtimeTargets` for one stop
  and one arrival time and reads back the lines, whether an unnamed line forces an unrestricted board, and the
  trips. `JourneyPlanningSession+Realtime.swift` shares the reachability helper. `RoutingDiagnostics` gets a
  `connectionLines` span (2.8–3.3 ms per search).
- Tests (`ConnectionLineFilterTests`, 5): the rule's lines and trips, the unnamed line, a Héienhaff-like
  fixture (the delayed connecting line is only on the transfer stop's board, which discovery did not fetch),
  both for the waves (departAfter and arriveBy) and for the speculative completion (one authoritative pass),
  and staying aboard a continuing trip. The end-to-end tests fail on the unchanged engine and the
  continuation test fails without its guard (mutation checks). Full suite, serial,
  `ROUTING_VERIFY_KERNEL=1`: **320 tests in 65 suites pass**.

## Replay mode added to the harness (app, not committed)

`Scripts/benchmark_routes.py --replay-approximate` (env `ROUTING_BENCHMARK_REPLAY_APPROXIMATE=1`): a board
query that was never recorded is assembled from recorded boards **of the same stop and window**, row by row for
each requested line. **It is approximate.** It holds the rows of the lines some recorded board covers, each as
observed when that board was recorded; lines no recorded board covers get no rows (listed as
`missingLines`). The answer's network time is the slowest source board's, or `--replay-approximate-latency
STOP=MS,…|*=MS` for a sensitivity run. Every query it answers is written to `approximate-queries.json`, every
replayed query to `replay-queries.json`. Without the flag a missing query still aborts the run.

## Which queries are new

[`new-queries.json`](new-queries.json), [`query-differences.json`](query-differences.json). In all four
captures exactly two boards change, the two transfer stops of the selected itineraries:

| Capture | Stop | Base asked | CAND-28 asks | Lines with recorded rows | Lines without |
|---|---|---|---|---:|---:|
| Thursday | Senningerberg, Héienhaff `000200508016` | `16`, then `6` (wave 1) | 16, 223, 29, 361, 6, 850 | 2 | 4 |
| Thursday | Kirchberg, Luxexpo `000200417050` | `21,6` | 33 lines | 2 | 31 |
| Sunday, rounds 1–3 | Héienhaff | `16,6` | 16, 223, 29, 361, 6, 850 | 2 | 4 |
| Sunday, rounds 1–3 | Luxexpo | `21,6` | 16 lines | 2 | 14 |

INV-6 in the replays: every query Base made is covered by a CAND-28 query at the same stop and window with a
superset of its lines (all 8 samples' query lists compared, 0 uncovered).

## Results

36 sample pairs (4 captures × 3 runs × priming, warm, cold), Base against CAND-28, run back to back.
[`runs.json`](runs.json) has every sample.

| | Base | CAND-28 |
|---|---|---|
| Authoritative passes per search | 2 in all 36 | **1 in all 36** |
| `networkRequests` | 27 (every capture) | Thursday **26**, Sunday 27 (the wave's board was a cache hit: 4 → 3 hits) |
| Journeys, recommendation, live coverage of shown legs | — | identical in all 36 pairs |
| `responseBytes` as measured | 17.87 / 6.63 / 6.44 / 6.45 MB | +0.05 / +0.03 MB (the assembled boards hold rows of 2 lines only) |
| `responseBytes` estimated for the real boards | — | Thursday **+3.1 MB (+17 %)**, Sunday **+0.9 to +1.0 MB (+14 %)** |

The estimate: the departures the rule's lines have at the stop in the board's window, from the installed
timetable (Thursday 62 at Héienhaff and 140 at Luxexpo; Sunday 41 and 38), times the mean decoded size of a
captured row of that line (19.5 KB; 18.3 KB on Sunday), minus the boards no longer fetched. Uncertainty about
±25 %. Gzip bytes on the wire grow by about the same share.

Totals, ms, medians of the runs whose transfer-walk build (CPU canary) was within 20 % of 1.95 s:

| | Priming | Warm | Cold |
|---|---:|---:|---:|
| Thursday Base (n = 3) | 3,829 | 3,243 | 3,687 |
| Thursday CAND-28, boards answered as the narrow boards were | 2,935 | 2,420 | 2,864 |
| Δ | −894 | −823 | −823 |
| Thursday CAND-28, boards answered after a modelled 1.15 s and 1.85 s (n = 2) | 3,448 | 2,949 | 3,462 |
| Δ | −381 | −294 | −225 |
| Sunday rounds 1 / 2 / 3, Δ | −50 / −205 / −108 | −177 / −250 / −134 | −384 / −204 / −160 |

Sunday passes cost only 130–150 ms, so the gain there is small. **The second pass disappears; how much of the
gain remains depends on how slowly ATP answers the two wider boards**, which a replay cannot show:

- The replay answers an assembled board after the slowest recorded source's time (0.3–0.4 s on Thursday).
  The wider boards hold 60 to 140 rows, not 12 to 22. A least-squares fit on the capture's own boards gives
  589 + 9.0 ms per row (r = 0.55, 73 boards) on Thursday and 1,116 + 11.5 ms per row (r = 0.19) on Sunday,
  hence the modelled 1.15 s and 1.85 s above. The fit is weak; treat it as a scale, not a prediction.
- Sweep, Thursday, every assembled board answered after X ms: X = 0.4 to 1.2 s keeps −0.4 to −0.8 s; 1.6 s
  −0.55 to −0.65 s; 2.0 s about −0.1 s; **2.2 to 2.4 s is worse than Base (+0.3 to +0.9 s)**. Break-even about
  2.0 s per board on the simulator. The live phase is network bound, so a slower board lengthens the
  speculative fetch, which is on the critical path in warm and cold. On the iPhone the second pass, wave and
  build cost 1.25 s, so the break-even is probably higher there; not measured (the device script has no
  approximate mode).
- Decode and matching of 3 MB more per search (estimated) are not in the replay either.

## What can change in live behaviour, and why

1. **The transfer-stop boards are wider** (lines and trips as above). Today a selected transfer ride is
   checked on its own line only. This is the intended change; the cost is board size and latency.
2. **Results can differ wherever one of the extra lines has live data that routing uses**: a delayed or early
   connection that is only now seen becomes feasible or drops out in pass one, a cancelled line is known
   earlier. Today those rows are learned only if a wave happens to select that line. That is more live data,
   not less; in the replays only the rows of lines 16 and 6 were available and no journey changed.
3. **Fewer passes and waves** when the wave only existed to learn those rows; never more requests (the same
   stops, windows and caps), and the first ride's board is unchanged. `networkRequests` can fall by the wave's
   board, `responseBytes` rises.
4. **Unchanged limits**: a connecting vehicle scheduled before the selected ride's window start is still not
   in any window (the windows are the selected ride's, as today). The rule is optimistic: at a hub it names
   every line that can still reach the destination (Luxexpo: 33 lines in the evening rush).

## Method and caveats

- Machine: MacBook Air M4, iPhone 17 simulator, mains power, Low Power Mode off, nothing else running.
  Transfer-walk build (canary) 1.85–2.32 s in the 35 runs used for timings. Dropped from the timings for a
  canary above 2.35 s: `S1-Base-r2` (2.38), `S2-Base-r0` (2.38), `S2-C28-r0` (2.46), `T-C28M-r0` (3.16); their
  counters agree with the other runs.
- Base is the engine at `1779b82` unchanged; CAND-28 is `1779b82` plus the files above only. During the work a
  second session edited `HafasRealtimeRoutingProvider*.swift` in the shared checkout (platform signal). Runs
  made with a build that contained it were discarded and redone from a tree built from `git archive HEAD` plus
  the CAND-28 files.
- Recommendations differ between repeated Sunday replays within one arm (wall-clock `now`, see the replay
  caveats); the comparison is therefore by pair of runs made back to back.
- `simctl launch --console` sometimes fails with "File exists" (FIFO); those runs were repeated.
- Raw bodies and bike snapshots stay outside git in `~/Developer/Verkeier-captures/`.
