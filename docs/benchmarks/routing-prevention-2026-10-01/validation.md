# Routing prevention delivery validation

Measured 1 October 2026 using MobiliteitKit runtime revision `6492c36fd02a8db53e96dfe3880a62b774d6691a`, Verkéier source milestone `3427ef1` and pin milestone `f4ab96c`. The final app pin is `8bf4741`; that follow-up adds only installed replay tests. `git diff 6492c36 8bf4741 -- Sources Package.swift` is empty, so the measured production sources and manifest are identical. The app uses a remote revision requirement; no local Swift package override remains.

## Environment and datasets

- iPhone 17 simulator, iOS 27.0, simulator UDID `F726825E-2DB4-4F45-A51C-DBA5AA0E2664`.
- Xcode 27.0 (`27A266a`), macOS 27.0.1 (`26A434`), `Mac16,12`, 16 GiB RAM.
- Release build, code coverage disabled, no debugger attached. No concurrent builds or tests during timed measurements.
- Previously installed Luxembourg GTFS feed, generation 3, service dates 24 September–12 December 2026. No GTFS download during the run. The SQLite backup used by the separate installed-feed replay has SHA-256 `4cc3b13e437f883620cd262fa9ded30b4d1e3d401561040e101c5a41a152bc44`.
- Previously installed Luxembourg walking tiles, dataset version `20260921`, Valhalla mobile `0.6.3`, core `3.6.3`.
- ATP requests use the existing recorded `esch-delayed-passlist.json` fixture and empty boards. The deadline scenario deliberately leaves boards unanswered to exercise the full two-second app acquisition budget. No live ATP requests or credentials are used.

## Method

Run `Scripts/benchmark_routes.py` with its defaults: ten scenarios, 20 timed warm operations after one discarded priming operation, and ten fresh app processes per scenario. The 300 timed operations include schedule/graph preparation, endpoint routing, recorded realtime acquisition/discovery, RAPTOR, validation/choice policy, adapter publication and first rendering in the visible production route sheet. Geometry refinement remains outside the gate and settles between samples.

Cold means a fresh app process with installed datasets; OS filesystem caches may be warm. Paging and refresh first calculate their prerequisite page. The simulator harness uses the real route view model, adapter, package router and local walking graph. It defers ordinary startup preparation so that the first operation pays that cost. It does not mount the main map behind the sheet.

P95 uses nearest rank; with ten cold samples, p95 is the maximum. The gate is **5,000 ms for each scenario and process group**, including the full realtime deadline. Raw samples retain timing stages, rounds, counters, option identifiers, unique request IDs and peak resident memory. A new request ID and a rendered, nonempty result with loading finished are required for every operation. Recorded-live additionally requires matched prediction events.

## Verification

[verification.txt](verification.txt) records the passing package, app, installed-feed and Release-build gates. Supplemental replay covers actual circular, midnight, overflow, first/last-service and cancelled trip instances selected from this feed; the cancellation overlay is an explicit fixture. [The implementation report](../../ROUTING_FAILURE_PREVENTION_IMPLEMENTATION.md) maps all 49 cases to executable regressions and records provider/accessibility contract limits. Timing evidence demonstrates simulator performance under this matrix; it does not establish every possible real-world journey or elevator state.

## Results

All **300 timed operations** completed and all **20 scenario/process p95 gates passed**. Ten discarded priming operations are also retained in `samples.jsonl`, marked `process: priming`. The worst p95 was 4.787 seconds (deadline-arrive cold); the acceptance limit remains five seconds. Peak resident memory reached 987.3 MiB across the run; this is simulator process high-water memory, not an on-device memory guarantee.

| Scenario | Warm p95 (s) | Cold p95 (s) |
|---|---:|---:|
| depart | 0.996 | 1.996 |
| reverse | 1.098 | 1.842 |
| coordinates | 1.031 | 1.588 |
| arrive | 2.378 | 2.972 |
| exact | 0.570 | 1.113 |
| rural | 0.538 | 1.096 |
| paging | 1.730 | 1.748 |
| refresh | 0.559 | 0.562 |
| recorded-live | 0.587 | 1.110 |
| deadline-arrive | 4.222 | 4.787 |

Every sample has a distinct request ID. Recorded-live samples contain matched predictions; the silent-board scenario charges the full acquisition budget. Stage medians, bounded search round work, rejected/duplicate counts, shared-first groups, recommendation switches and page progress remain visible in [summary.json](summary.json) and [samples.jsonl](samples.jsonl). The final runtime source includes publication-time evidence expiry; the incomplete earlier run before that fix is excluded.
