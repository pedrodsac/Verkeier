# Step 7 live re-baseline, simulator (Tuesday 20 October 2026)

Step 7 of [ROUTING_SPEED_PLAN.md](../../ROUTING_SPEED_PLAN.md): live `live-now` searches with every committed
change so far: steps 0–2, the direction guard, `GeodesicDistance`, CAND-28 and CAND-5.

- **Route:** Gromscheed → Kirchberg, Konrad Adenauer, leave now, on a weekday evening. Planning times:
  round 1 at 18:52, rounds 2 and 3 at 19:05–19:06. This is later than the 17:51 Thursday baseline and the 17:45
  that was planned; see "Attempts" below.
- **Build:** Release simulator app from a clean export of Verkeier `d0d58d5` plus the git-ignored walking graph
  files. MobilitéitKit `83ecb6b`, packages cloned fresh from `Package.resolved`. Feed
  `gtfs-20261014-20261212` (generation 1), installed in the simulator's container.
- **Machine:** MacBook Air M4, iPhone 17 simulator, mains power, Low Power Mode off, thermal state nominal in
  every sample, no other build or benchmark running. Transfer-walk build (the CPU canary): 2,304 / 2,246 /
  2,693 ms for the live rounds and 2,217 / 2,709 / 2,190 ms for the replays.
- **ATP requests:** 240 in all (78 + 81 + 81), against about 245 approved. The replays sent none.
- **Command per round:** [`run.sh`](run.sh), which wraps `Scripts/benchmark_routes.py --scenarios live-now
  --warm 1 --cold 1 --maximum-limit-ms 0 --request-budget 100`. Each live round is then replayed from its own
  capture with `--replay-latency --request-budget 0`.

## Attempts

The one-time task fired too late, at 18:51 instead of 17:41, and the script refused because the Mac was on
battery. A second start at 18:52 ran live round 1 (78 requests). Then the script crashed: in zsh, `status` is a
read-only variable, so `status=$?` aborted it. With the fix, and a check that never repeats a finished round,
the owner approved rounds 2 and 3, which ran at 19:05–19:06.

## Results

| Sample, ms | Round 1 (18:52) | Round 2 (19:05) | Round 3 (19:06) | Median | Maximum |
|---|---:|---:|---:|---:|---:|
| Priming | 2,914 | **5,490** | 4,959 | 4,959 | 5,490 |
| Warm | 2,141 | 4,792 | **7,480** | 4,792 | 7,480 |
| Cold | 2,562 | 4,629 | 3,909 | 3,909 | 4,629 |

**Gate check:**

| Criterion | Result |
|---|---|
| Every operation < 5,000 ms | **Fail.** 2 of 9 are over: priming in round 2 (5,490) and warm in round 3 (7,480) |
| Warm median ≤ 4,000 ms | **Fail** (4,792) |
| Cold median ≤ 4,000 ms | Pass (3,909) |
| Warm and cold maximum ≤ 4,500 ms | **Fail** (warm 7,480; cold 4,629) |

**Round 1 alone** passes every criterion, at 2.1–2.9 s.

**What the client did, every sample:**
- One authoritative pass.
- 26–27 requests, 14.4–15.6 MB decoded.
- 5 journeys, every one with live coverage.
- All requests returned HTTP 200, with no incomplete boards.
- The scan took 219–302 ms. `snapshotPreparation` was 0–90 ms (CAND-5) and `walkingPreparation` 242–356 ms.

Total minus the realtime stage is 0.4–0.8 s in every sample.

## Why rounds 2 and 3 were slow: the server, not the client

| | Round 1 | Rounds 2 and 3 |
|---|---:|---:|
| Median server wait per board | 0.4–1.1 s | 1.5–3.7 s |
| Median transfer per board | 14–20 ms | 0.2–1.0 s |
| Realtime stage | 1.7–2.1 s | 3.3–7.1 s |

- **Every board slowed down,** narrow single-line boards included. So the slowdown was not caused by CAND-28's
  wide boards.
- **The widest board still hurts most.** The Luxexpo board CAND-28 widens to 33 lines (`000200417050`, 138 KB
  gzip) was the slowest board in 5 of the 6 slow samples: 2.1–4.0 s wait plus 0.8–2.6 s transfer. In round 1
  it was not, at 1.1–1.2 s wait plus 0.08–0.14 s transfer.
- **The worst sample would not have passed with a narrower Luxexpo board either.** In the 7,480 ms warm sample
  of round 3, the next two boards took 6.5 and 6.3 s.
- **The cause is unknown.** Wait and transfer times are measured on the client, so they can't say whether ATP,
  the relay Worker or the network path was slow (plan §7, item 3: a `Server-Timing` header would). It could
  also be ATP rate-limiting. Rounds 2 and 3 sent 162 requests within about a minute, while round 1 ran alone.

## Replays

The replays used the recorded bodies and their recorded latency.

- **Results are identical:** all 9 samples have the same journeys and recommendation as their live sample.
- **CPU stages match live:** the scan took 218–284 ms against 219–302 ms live.
- **Totals follow the recorded latency:**
  - R1: 2,161–2,515 ms.
  - R2: 4,243–4,515 ms.
  - R3: 7,229–7,408 ms. Here the loader's first-body-per-query rule picked mostly the slow warm sample's
    latencies (see [route-replay caveats](../live-2026-10-18/README.md)).

## Comparison

| Run | Medians, priming / warm / cold, ms | Board data | Passes |
|---|---|---:|---|
| Thursday 15 October 17:51 (baseline, n = 1, busy machine) | 10,058 / 7,053 / 7,655 | 17.9 / 10.7 / 17.9 MB | 2 per search |
| Sunday 18 October (after step 2, before CAND-28) | 3,161 / 2,110 / 2,961 | 6.4–6.6 MB | 2 per search |
| Tuesday 20 October, this run | 4,959 / 4,792 / 3,909 | 14.4–15.6 MB | 1 per search |

## Files

| File | Content |
|---|---|
| `L<n>/`, `R<n>/` | `samples.json` (every sample: spans, passes, counters, journeys, per-request URLSession timestamps), `summary.json`, `transport.json` (metadata of every ATP response, no bodies), `optimisation.json` (canary) |
| `run.log`, `run-attempt-1852.log` | Script output of the two runs that passed the guards |
| `run.sh` | The script as it ran rounds 2 and 3 |

The raw bodies, bike snapshots and the two app builds are outside git, in
`~/Developer/Verkeier-captures/step7-2026-10-20/`.
