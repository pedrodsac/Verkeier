# CAND-12 (a) relay trimming, offline check (Thursday 29 October 2026)

I trimmed the recorded ATP boards of eight live captures to the fields routing reads, then replayed each capture
twice with recorded latency: once with the original bodies and once with the trimmed ones. No ATP request was
sent and the relay was not changed. See CAND-12 (a) in §4.5 of [ROUTING_SPEED_PLAN.md](../../ROUTING_SPEED_PLAN.md).

**Result in one line:** trimming changed no routing result in 63 sample pairs. It cuts decoded bytes by
71–75 % and client decode time by about 60 ms per search, but the total doesn't move measurably. Whether it
shortens slow-period transfers can't be told offline.

- **Code:**
  - Capture-era build: the Release simulator build of Verkeier `fa5833b` with MobilitéitKit `00078b6`, from the
    20 October round (also used on 22 October).
  - Current build: Verkeier `f352e87` with MobilitéitKit `1bd2ebf`, from `git archive` plus the walking graph
    files, built with `ENABLE_CODE_COVERAGE=NO` ([`BUILD.txt`](BUILD.txt)). My first build left that flag out and
    had coverage instrumentation (`-profile-coverage-mapping`, probably from the scheme's test plan). That made
    pass and walking work 0.5–1.3 s slower per sample. Its 18 sample pairs were identical too, but its timings
    aren't used here.
- **Machine:** MacBook Air M4 with the iPhone 17 simulator, on battery power, Low Power Mode off. Each run
  waited (up to 3 minutes) for the 1-minute load to drop below 6. CPU canary 1.87–2.54 s.
- **ATP requests:** 0. Every replay used `--request-budget 0`. Every query was recorded, so no replay needed
  `--replay-approximate`.
- **Captures:** `st-L1` (20 Oct 20:57), `s7-L1`, `s7-L2`, `s7-L3` (step 7, 20 Oct 18:52 and 19:05–19:06),
  `c28-now`, `c28-rev`, `c28-esch` (19 Oct), `st22-L2` (22 Oct 18:55). All use timetable generation 1, which is
  still the one installed in the simulator.

## Trim rule

Only these fields are kept. Everything else is dropped.

| Level | Kept |
|---|---|
| Board | `Departure`, `errorCode`, `errorText` |
| Departure | `JourneyDetailRef.ref`; the first `Product` with `name`, `line`, `lineId`, `catOutS`; `Stops.Stop`; `stopExtId`, `time`, `date`, `rtTime`, `rtDate`, `prognosisType`, `cancelled`, `reachable`, `direction`, `platform.text`, `rtPlatform.text` |
| Passlist stop | `name`, `extId`, `routeIdx`; `dep`/`arr` and `rtDep`/`rtArr` times and dates; `depTrack`, `arrTrack`, `rtDepTrack`, `rtArrTrack`; `depPrognosisType`, `arrPrognosisType`; `cancelled`, `cancelledDeparture`, `cancelledArrival`; `boarding`, `alighting`, `rtBoarding`, `rtAlighting` |

- **Source:** the Decodable models in `MobiliteitAPIClient.swift` at `1bd2ebf`, reduced to the fields read by
  `DepartureBoardCache`, `DepartureBoardSnapshot`, `CachedBoardResponse` and `HafasRealtimeRoutingProvider*`.
  Those files hold every routing use of the board models.
- **Passlist `id`** is compared in `sameStopID`, but it is always `A=…@L=…`. It is never numeric, so it never
  equals a GTFS stop ID. `extId` is present wherever `id` is, in all 483 bodies.
- **`Product`:** the engine reads only the first element. No row had more than one.
- **`1bd2ebf`'s platform signal** (`hasPlatformSignal`) reads `platform.text`, `rtPlatform.text` and the
  `*Track` fields, which are all kept.
- **Largest shares dropped,** measured on `st22-L2` as a share of all bytes:
  - the passlist's `mainMast*` fields: about 30 %;
  - the platform objects (`depPlatform` and the like): about 10 %;
  - the passlist `id`: 6 %;
  - `altId`: 4 %;
  - `ProductAtStop`: 3.4 %;
  - `minimumChangeDuration`: 2.5 %;
  - `Notes`: 1.6 %.

## Bytes

| Capture | Bodies | Decoded, MB | brotli -q 4, MB | gzip -6, MB | Recorded on the wire, MB |
|---|---:|---|---|---|---:|
| `st-L1` | 78 | 27.2 → 7.7 (−72 %) | 1.10 → 0.39 | 2.61 → 0.50 | 1.39 |
| `s7-L1` | 78 | 46.9 → 13.5 (−71 %) | 1.57 → 0.62 | 4.56 → 0.81 | 2.05 |
| `s7-L2` | 81 | 43.1 → 12.4 (−71 %) | 1.52 → 0.59 | 4.22 → 0.76 | 1.97 |
| `s7-L3` | 81 | 43.5 → 12.6 (−71 %) | 1.53 → 0.59 | 4.26 → 0.77 | 1.98 |
| `c28-now` | 27 | 15.7 → 4.5 (−71 %) | 0.53 → 0.21 | 1.53 → 0.27 | 0.68 |
| `c28-rev` | 29 | 18.1 → 5.2 (−71 %) | 0.64 → 0.25 | 1.71 → 0.34 | 0.83 |
| `c28-esch` | 25 | 10.4 → 2.6 (−75 %) | 0.36 → 0.14 | 1.03 → 0.17 | 0.46 |
| `st22-L2` | 84 | 48.9 → 14.0 (−71 %) | 1.70 → 0.66 | 4.79 → 0.86 | 2.21 |

- **Wire size:** the recorded size doesn't match any single codec. For `st22-L2` it is 2.21 MB, which falls
  between brotli -q 2 (2.73 MB) and -q 3 (2.00 MB) and above zstd -1 (1.94 MB). The trimmed bodies compress to
  0.63–0.82 MB with those codecs. So the bytes on the wire would fall by roughly 63–71 %, as an estimate.
- **Body sizes:** the median body is 346 KB decoded. The largest is 3.14 MB, the Luxexpo hub board
  `000200417050` on 19 October, which trims to 0.88 MB.

## Results: identical

Each sample pair compared the following:
- the result fields: `unfilteredJourneys`, `journeys`, `options`, `recommendedOption`, `realtimeCoverage`,
  `matchingRejections`, `displayedLegs`, `supplementalOptions`, `canLoadEarlier` and `canLoadLater`;
- pass and warm-up pass counts;
- the arrival order of boards;
- every counter except `responseBytes`.

| Build | Sample pairs | Identical | Differing |
|---|---:|---:|---|
| Capture-era (`00078b6`) | 27 | 22 | 5, all `s7-L2`: counters in 4, board arrival order in 1 |
| Current (`1bd2ebf`) | 36 | 32 | 4, all `s7-L2`: counters only |

- **The result fields were identical in all 63 pairs.**
- **The other seven captures matched in every counter too.**
- **The original-body replays reproduce the live captures:** the same engine journeys and request counts in
  every sample. `responseBytes` differs from live in some `s7-L2` and `s7-L3` samples. Repeated queries resolve
  to the first recording in filename order, so the replay serves one body per query in all three samples. That
  holds for both arms.
- **`s7-L2`'s counters vary between replays of the untouched bodies as well.** In both arms, the most common
  values of `duplicatesSuppressed` / `predictedEvents` were 945 / 3,759:

  | Arm (21 samples each) | 945 / 3,759 | 949 / 3,757 | 965 / 3,756 | 949 / 3,742 | 945 / 3,758 |
  |---|---:|---:|---:|---:|---:|
  | Original bodies | 17 | 2 | 1 | 1 | 0 |
  | Trimmed bodies | 15 | 1 | 3 | 0 | 2 |

  With 965, `invalidJourneys` also drops from 162 to 141. Journeys and live coverage are identical in all of
  these samples.
  - This looks like the order-sensitive realtime race described under "Round-3 +4 counters" in the plan:
    equal-rank board rows decided by microsecond timing. I haven't traced which rows are involved.
  - Faster decoding shifts the timing, so the mix of variants can move. The two variants seen in only one arm
    occur once (949 / 3,742) and twice (945 / 3,758).

## Timing (current build, 36 pairs)

| | Median change | Range |
|---|---:|---:|
| `decode` (summed over boards, concurrent) | −61.5 ms | −107 to −5 ms |
| Total | −20 ms | −602 to +59 ms |
| Peak memory | −13 MB (about 2 %) | −20 to +41 MB |
| `providerBoardPreparation` | +0.2 ms | −16 to +7 ms |

- **Capture-era build:** decode changed by a median of −59 ms and the total by −26 ms.
- **The total doesn't move beyond replay noise** (10–20 %). The −602 ms is `st22-L2`'s first priming sample, whose
  original-body run was slow: 2,972 ms, against 2,349–2,452 ms in its other seven runs.
- **Why the total barely moves:** most decoding overlaps the wait for other boards. Only the decode of the boards
  that arrive last sits on the critical path. On a 6-core iPhone the decode share is larger. That wasn't measured.

## What this check can't show: transfer time

The replay answers each board after its recorded wait and transfer, so trimmed bodies arrive when the originals
did. Live, the Worker would have to read the whole ATP body before it can send the trimmed one. Today it streams
the body through.

- **In both Server-Timing rounds, transfer per board stayed small:** a median of 11–13 ms. Even when ATP's
  header wait was over 800 ms, the median was only 26–60 ms. Buffering the body would cost little then.
- **In step 7's slow rounds (19:05), transfer was slow:** a median of 317–331 ms per board, about 80 KB/s for
  bodies over 50 KB, against 1.0–1.5 MB/s at 18:52. Server-Timing didn't exist yet.
  - If that time was ATP sending slowly, a trimming Worker would wait for it just the same.
  - If it was the leg from Cloudflare to the client, trimming would cut it roughly by the byte ratio.
  - These data don't say which.
- **A trimming Worker could time its own read of the ATP body.** Each read is I/O, so the Worker's clock
  advances. It could then report that time in Server-Timing, which would settle the question.

## Still open before a live change

These are the plan's requirements, now with the numbers above:
- An opt-in URL parameter with its own `BoardCacheScope` namespace, so the UI never receives trimmed boards.
- Worker CPU: the Worker must parse up to 3.14 MB of JSON per board (median 346 KB). Parsing a 2.6 MB body took
  13 ms in Python on this Mac. Check this against the Worker plan's CPU limit.
- ATP's terms.

## Files

| File | Content |
|---|---|
| `tools/trim.py` | The trim rule. It writes a trimmed copy of a capture and `trim-stats.json`, and never writes below the source |
| `tools/replay.sh`, `tools/batch.sh` | One replay; the original/trimmed batches, in ABBA order per capture. The paths point to this session's scratch folder |
| `tools/compare.py` | Pairs the original and trimmed runs and checks the originals against the live capture |
| `results/compare-capture-era.json`, `results/compare-current.json` | Every sample pair: identity, differences, timings and bytes |
| `results/trim-totals.json` | Byte totals and rule checks per capture |
| `BUILD.txt` | The current build |

The runs (samples, logs, no transfer-walk stores) are in
`~/Developer/Verkeier-captures/cand-12a-offline-2026-10-29/`, outside git. The trimmed captures can be rebuilt
with `trim.py`.
