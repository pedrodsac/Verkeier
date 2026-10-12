# Three journey benchmarks — 12 October 2026

Departure fixed at **2026-10-12T18:16:07+02:00**, Europe/Luxembourg. All three live searches completed and rendered transit results.

| Journey | Live first render | Four fresh-process replay median | Displayed / unfiltered journeys | Five-second live gate |
| --- | ---: | ---: | ---: | --- |
| Gromscheed → Kirchberg, Konrad Adenauer | 7.337 s | 3.403 s | 5 / 6 | Fail |
| Sandweiler-Contern, Gare routière → Lorentzweiler, Gare | 5.221 s | 2.209 s | 2 / 6 | Fail |
| Beiler, Bei der aler Schull → Rumelange, Märtyrerstrooss | 8.574 s | Unavailable: strict replay aborted | 1 / 6 | Fail |

## Measurement setup

iPhone 17 simulator (`F726825E-2DB4-4F45-A51C-DBA5AA0E2664`), iOS 27.0. Release, coverage disabled, no debugger, production service composition, full map and route sheet. Installed GTFS generation 5 and walking graph version 20260921. Each accepted operation ran in a fresh app process; filesystem caches may be warm. These are simulator results, not physical iPhone measurements.

App base commit `468cc78b022cf6dca1da629d5417d5edae2ac0b6`; MobiliteitKit `562bca26973968113cc6c5d9d69228142c8819d5`. The build includes the pre-existing uncommitted route-view edits identified in metadata, plus benchmark-only custom-origin support. Release build passed before timing began. Full canonical plan export was enabled; peak memory is not an isolated memory benchmark.

One live capture per journey, followed by four offline replays at the same timestamp with the captured boards and bike snapshot. The first replay is labelled `priming` by the runner but is included in this report’s four fresh-process median. Live and offline latency are reported separately. The runner’s latency rejection was disabled (`--maximum-limit-ms 0`) to retain slow samples; every live sample exceeds the normal 5,000 ms gate. A single live sample is not a percentile estimate.

The three live operations used 124 ATP requests total. Recorded transport, complete canonical plans, logs and bike snapshots remain at `/tmp/verkeier-three-benchmarks-2026-10-12`; the committed capture manifest records response-body hashes without copying raw responses.

## Stage timings

Milliseconds; stages overlap or nest, so do not sum them. Walking transfers are included in RAPTOR.

| Stage | Gromscheed | Sandweiler-Contern | Beiler |
| --- | ---: | ---: | ---: |
| Snapshot preparation | 363.4 | 295.3 | 320.3 |
| Walking graph preparation | 153.9 | 80.5 | 85.2 |
| Endpoint walks | 110.3 | 79.2 | 77.9 |
| RAPTOR, including walking transfers | 2137.6 | 1278.5 | 113.2 |
| Walking transfers | 1461.0 | 1095.0 | 64.0 |
| Candidate building | 226.9 | 75.7 | 93.3 |
| Realtime acquisition and processing | 4113.0 | 3301.5 | 7730.6 |
| Render after publication | 206.3 | 92.7 | 110.0 |

Realtime accounts for 4.113 s, 3.301 s and 7.731 s respectively. The long-distance Beiler route spends only 0.113 s in RAPTOR in this sample. These measurements identify the dominant recorded stages; they do not establish a general performance distribution.

## Replays and route evidence

The Gromscheed and Sandweiler replays match their live captures exactly for complete canonical transit and supplemental plans, displayed journeys, option IDs, leg timing/source evidence, realtime coverage and all counters. Every accepted replay is below five seconds. Individual replay timings in milliseconds:

- Gromscheed → Kirchberg, Konrad Adenauer: 3422.290, 3383.792, 3430.903, 3322.956.
- Sandweiler-Contern, Gare routière → Lorentzweiler, Gare: 2208.824, 2210.159, 2186.286, 2741.069.

Beiler’s first strict replay requested board queries absent from its live capture and aborted. It issued no additional ATP requests. Its attempted replay is excluded from timing summaries; no equivalent replay result is claimed. Missing queries are recorded in `summary.json`. The exact reason its acquisition queries differed was not established by this benchmark.

Displayed journeys in the live samples:

**Gromscheed → Kirchberg, Konrad Adenauer**

- walk → 322 → 29 → 16: 18:17:21–18:46:00.
- walk → 322 → 21 → walk: 18:17:21–18:50:13.
- walk → 850 → 6: 18:21:45–18:54:00.
- walk → 326 → walk → 18: 18:32:21–18:59:00.
- walk → 321 → walk → 18: 18:37:45–19:09:00.

**Sandweiler-Contern, Gare routière → Lorentzweiler, Gare**

- walk → RB → RB: 18:36:31–19:08:00.
- walk → RB → RB: 19:05:31–19:38:00.

**Beiler, Bei der aler Schull → Rumelange, Märtyrerstrooss**

- 175 → walk → IC → walk → 508: 20:04:50–22:36:15.

The adapter exported six unfiltered candidates per journey; the table separately counts what the production sheet displayed. No comparison against an external journey planner was performed.

## Evidence and reproduction

- `metadata.json`: timestamp, coordinates, GTFS IDs, build and local artifact locations.
- `samples.json`: all 11 accepted samples, stages, counters, displayed journeys and canonical-plan hashes.
- `summary.json`: live timings, all accepted replay timings, equality checks and missing replay queries.
- `capture-manifest.json`: 124 live response-body hashes.

Build with:

```sh
xcodebuild -project Verkeier.xcodeproj -scheme Verkeier -configuration Release \
  -destination 'platform=iOS Simulator,name=iPhone 17' ENABLE_CODE_COVERAGE=NO build
```

Run `python3 Scripts/benchmark_routes.py` with `--scenarios live-depart --warm 0 --cold 0 --full-map --full-evidence --maximum-limit-ms 0`, the fixed `--time`, and endpoints from `metadata.json`. Custom origins accept `--origin-name`, `--origin-coordinate LAT LON` and `--origin-stop`. Replay the first two captures with `--capture-directory <live/network> --bike-fixture <live/bike-snapshot.json> --request-budget 0 --cold 3`. This performs four fresh-process operations, including the runner’s priming sample. A new live capture has changing realtime inputs and is not an exact reproduction.
