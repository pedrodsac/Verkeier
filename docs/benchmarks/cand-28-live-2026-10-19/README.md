# CAND-28, live union capture (Monday 19 October 2026, 18:43–18:47)

Approved by the owner: up to 120 ATP requests, three routes, one live CAND-28 priming search each
(`--warm 0 --cold 0 --request-budget 40`), weekday evening. **81 requests were sent** (27 + 29 + 25).
MacBook Air M4, iPhone 17 simulator, mains power, Low Power Mode off, nothing else running; transfer-walk
build (CPU canary) 1.98–2.27 s for the live runs. App: Release build of the CAND-28 engine (MobilitéitKit
`1779b82` + the CAND-28 files, not committed) with the replay harness of
[`../cand-28-offline-2026-10-18/`](../cand-28-offline-2026-10-18/README.md). The raw bodies are outside git in
`~/Developer/Verkeier-captures/cand-28-live-2026-10-19/`; [`results.json`](results.json) has the numbers below.

Before the run the simulator had no timetable (its app container had been reset). One normal launch of an
install-only build with the relay URL emptied downloaded the public GTFS feed
(`gtfs-20261014-20261212.zip`, generation 1) from data.public.lu; it could not reach the relay, so it sent
no ATP request. A first attempt of the runner stopped at `timetableUnavailable` before any request.

## Method

The CAND-28 arm ran live. Both arms were then replayed from that capture, with recorded latency and the
capture's planning time. CAND-28 exactly. Base with `--replay-approximate`: its narrow boards (`lines=6`)
are row subsets of the wide boards CAND-28 fetched, so the rows are exact (no line was missing); only their
latency is borrowed from the wide board. Base's own live timing on this evening was not measured.

## Results

| | `live-now` (Gromscheed → Kirchberg) | `live-reverse` | `live-esch` |
|---|---:|---:|---:|
| CAND-28 live: total, passes | 3,131 ms, **1** | 3,101 ms, **1** | 2,187 ms, **1** |
| CAND-28 live: requests, decoded MB | 27, 15.68 | 29, 18.06 | 25, 10.42 |
| Base on the same data: passes | **2** | 1 | 1 |
| Base on the same data: requests, decoded MB | 28, 13.46 | 29, 14.74 | 25, 10.42 |
| CAND-28 − Base, MB (share) | +2.2 (+16.5 %) | +3.3 (+22 %) | 0 |
| Journeys, recommendation, live coverage of shown legs | identical | identical | identical |
| Every Base query covered by a CAND-28 query (INV-6) | yes | yes | yes |
| Boards CAND-28 widened | 3 | 3 | none (no transfer ride) |

- **One authoritative pass in 3 of 3 live runs** (plan target: ≥ 2 of 3). But Base already needed only one pass
  on two of the three routes, so the second pass disappears where it existed: `live-now`.
- **Time.** `live-now`: CAND-28 3,131 ms live (3,112 replayed). Base replayed with the narrowed boards at the
  wide boards' recorded wait: 4,743 ms, which is pessimistic for Base; with the narrow boards answered after
  0.5 / 0.8 s: 3,416 / 3,717 ms. So the gain on `live-now` is about **−0.3 to −0.6 s** on the simulator (the
  Thursday baseline passes were heavier; the iPhone 13 second pass plus wave costs 1.25 s). `live-reverse`:
  3,142 against 3,170 ms (the Base replay's canary was 2.48 s, a bit hot), `live-esch`: 2,265 against
  2,354 ms: no pass saved, no loss.
- **Wide boards, live.** Luxexpo `000200417050`, 33 lines: 110 rows, 2.2 MB, wait + transfer 1.23 s
  (`live-now`); 155 rows, 3.1 MB, 1.75 s (`live-reverse`, the slowest board of that search). Héienhaff
  `000200508016`, 6 lines: 51 rows, 0.9 MB, 1.30 s. The side boards with 30-minute windows (12–13 rows) took
  0.3–0.6 s. Across all boards of a search: median 0.5–0.9 s, maximum 1.25–1.75 s. The Thursday sweep put the
  break-even at about 2.0 s per wide board, so these stay under it, by 0.25 to 0.8 s. The wide boards are
  1.4 to 2.2 times the median board; the Thursday row model (589 + 9 ms per row) predicted 1.6 and 2.0 s for
  110 and 155 rows, a little high.
- **Bytes.** Estimated +14 to +17 % offline; measured +16.5 % and +22 % where a hub board widened.
  `networkRequests` 28 → 27 on `live-now`, otherwise equal (≤ +20 % holds).
- **Journeys.** No shown journey changed on any route, although the wide boards carried the live rows of every
  qualifying line. `live-reverse` replays one more journey than the live sample (6 against 5, wall-clock
  `now`, known replay caveat).

## What it does and does not show

Shown: pass 2 goes away on the one route that had it, nothing is lost (INV-6, journeys, coverage), the wide
boards' live latency is below the break-even. Not shown: Base's live timing (one search per route and arm
on a different minute would have cost 81 more requests), the phone (no approximate mode in the device
script), a second evening, and routes whose hub boards are slower. The gain is small on the simulator and
route-dependent (1 of 3 here); on the iPhone the dropped pass is worth more.
