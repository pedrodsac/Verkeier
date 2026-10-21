# CAND-5, persisted routing snapshot (Monday 19 October 2026, 20:05–20:40)

Replays only: **no ATP request was sent.** The plan's CAND-5 (§4.6) stores the routing snapshot that
`TransitRouter` builds from the GTFS SQLite as one versioned binary file, so a cold start loads it instead of
rebuilding it. This folder holds the before/after numbers; [`results.json`](results.json) has every run.
The engine change is `83ecb6b` in `~/Developer/MobilitéitKit` (pushed); this repository pins it in `f7881b4` and wires the cache in `d0d58d5` (not pushed).

## What was measured

- **Arms.** *Base*: the app at HEAD plus MobilitéitKit `d8635e5` (`git archive HEAD`, which already contains
  CAND-28). *C5*: the same plus the CAND-5 engine files and the app wiring (cache directory
  `Caches/Mobiliteit/RoutingSnapshot`, also used by the simulator benchmark's service). Both are Release
  simulator builds from scratchpad copies with the engine as a local package; the foreign, uncommitted
  platform-signal edit in the engine checkout is in neither arm.
- **Inputs.** The live union capture of 19 October 18:43
  (`~/Developer/Verkeier-captures/cand-28-live-2026-10-19/`, routes `live-now`, `live-reverse`, `live-esch`),
  recorded against the installed generation 1 feed, replayed with `--replay-latency`, the capture's planning time and
  its bike snapshot. The stored transfer-walk table is built by the canary process of every run.
- **Protocol.** 3 routes × 5 repetitions × 2 arms = 30 runs, order alternating between arms and flipping from
  repetition to repetition, 25 s between runs. Each run is three launches: the transfer-walk build (CPU canary), a
  process with the priming sample and one warm sample, and a fresh process for the cold sample
  (`--warm 1 --cold 1`). The C5 file is in the simulator's Caches when each process starts (the steady state of every
  start after the first); the first-start case is measured separately below.
- **Machine.** MacBook Air M4, macOS 27.0.1, iPhone 17 simulator, **on battery power (64 %)**, Low Power Mode off,
  `mediaanalysisd` and Spotlight indexing busy for part of the series. Runs whose canary is more than 20 % above the
  median canary (2,758 ms) are dropped, as in the plan: 3 Base runs and 1 C5 run (canary 2,894, 3,000, 3,573, 3,749
  ms). Without any dropping the medians move by at most 17 ms (last bullet below).

## Result

Pooled medians over the three routes (kept runs: Base 12, C5 14; n = samples per kind), milliseconds:

| | Base | C5 | Δ | min–max Base / C5 |
|---|---:|---:|---:|---|
| **Cold `snapshotPreparation`** | 244 | **22** | **−222** | 240–264 / 21–37 |
| Priming `snapshotPreparation` (fresh process) | 248 | 45 | −203 | 242–259 / 21–56 |
| Warm `snapshotPreparation` | 0 | 0 | 0 | 0–1 / 0–1 |
| Live phase starts, cold | 315 | 114 | −200 | 305–348 / 107–194 |
| Live phase starts, priming | 319 | 127 | −192 | 308–342 / 106–146 |
| **Total, cold** | 2,959 | **2,786** | **−173** | 2,232–3,252 / 2,066–3,018 |
| Total, priming | 2,992 | 2,793 | −199 | 2,250–3,221 / 2,054–3,047 |
| Total, warm | 2,626 | 2,642 | +15 | 1,938–2,821 / 1,860–2,835 |
| Canary (transfer-walk build) | 2,265 | 2,353 | +89 | 2,233–2,530 / 2,244–2,591 |

Per route (cold total, Base → C5): `live-now` 2,959 → 2,786 (−173); `live-reverse` 3,171 → 2,986 (−184);
`live-esch` 2,293 → 2,072 (−222). Priming −199 / −168 / −164, warm +15 / +2 / −39.

- **Target.** Cold `snapshotPreparation` ≤ 300 ms (plan step 6): 22 ms in every sample (maximum 37); Base was
  already at 244 ms in these replays, so the target is met on the simulator with or without CAND-5. Plan row 14's
  866–916 ms of snapshot load is not reproduced here: the cold stage reads 244 ms, and the engine-level build takes
  ~230 ms on this machine (numbers below). The phone's stage was 429 ms (step 3), so the saving there should be larger;
  not measured, the device script was not run.
- **What the saving is.** The live phase now starts at ~114 ms instead of ~315 ms, a gain of about 0.2 s on cold and
  priming. That is less than the plan's 0.25–0.35 s because graph preparation (`graphPreparation` ≈ 33 ms) and
  endpoint preparation (≈ 70–80 ms, which waits for the walking graph) are now the limit, as the plan predicted. The warm
  sample does not touch the snapshot and is unchanged (+15 ms is inside the spread).
- **Canary.** The canary's build stage is the same in both arms (2,022 against 2,040 ms) and the +89 ms is inside
  the spread of both (2,233–2,591 ms); the warm totals, which are pure search CPU, show no slowdown (+15, +2, −39 ms
  by route). It is reported, not explained.
- **Without dropping any run** (15 + 15 runs): cold `snapshotPreparation` 245 → 22, cold total 2,965 → 2,784 (−182),
  priming total 3,000 → 2,810 (−190), warm 2,635 → 2,638.

## First start, and no stored table

`miss_run.sh`: the stored file deleted, then one fresh priming process and one fresh cold process (4 runs per arm,
`--transfer-walks off`, which leaves out the canary process). C5 priming `snapshotPreparation`
286 ms (265–341) against 282 ms for Base (250–322): a miss costs the identity check (0.3 ms) and nothing else,
because the store runs in the background. The file was complete before the next process started in both runs that
reached the cold sample (cold `snapshotPreparation` 28 and 22 ms).

With `--transfer-walks off` the walking provider is live and sometimes changes which Luxexpo board is requested, so a
replay can stop with `missing-replay-query`: C5 2 of 4 and 1 of 6, Base 0 of 4 and 1 of 6 in the two batches. It
happens in both arms, with the same query, and is the known walking-provider nondeterminism; it does not occur with
the stored table (0 of 30 runs, 90 samples).

## Exactness

| Check | Result |
|---|---|
| Journeys, recommended option, canonical plans, counters (`networkRequests`, `boardsCovered`, `candidates`, …) between Base and C5 | identical in all 15 sample pairs per kind for `live-now` and `live-reverse`; identical on `live-esch` except one recommendation switch (below) |
| `live-esch` recommendation | trip `24284821` becomes `24284820` between 20:24:14 and 20:24:52 in **both** arms (Base from r2, C5 from r3): the wall-clock `now`, not the arm; journeys and canonical plans are identical throughout |
| Snapshot, built by HEAD's builder against built by the refactored builder (26 table digests, real feed and fixture) | identical |
| Snapshot loaded from the file in a new process against HEAD's built snapshot (same 26 digests) | identical |
| `InstalledEquivalenceReplayTests` JSON (4 scenarios, 1.26 MB), HEAD against CAND-5 built and against CAND-5 with the snapshot loaded from the file | byte-identical, three-way |
| `ROUTING_VERIFY_KERNEL=1 swift test --no-parallel` | 342 tests, 68 suites pass (320 before, 22 new) |

## Engine-level numbers (host, Release test build, installed feed of 49.7 MB)

28,006 trips, 641,398 stop times, 2,805 stops, 1,748 patterns, 2,904 transfer rules.

| | |
|---|---:|
| File size | **17,613,944 bytes (17.6 MB)** |
| Build from the SQLite (3 runs; 226–252 ms in two sessions) | 228, 230, 252 ms |
| Load: identity check + map + checksum + decode (7 runs) | 13–19 ms (decode alone 9–10 ms) |
| Identity check (stat, SQLite header, metadata) | 0.3 ms |
| Encode / atomic write (once, in the background) | 30 ms / 33 ms |

In the simulator app the stage reads 22 ms because it also covers the router's other setup.
