# Live baseline: one route (15 October 2026)

One live search benchmark on the current code, used as the baseline in
[ROUTING_IMPROVEMENT_BRIEF.md](../../ROUTING_IMPROVEMENT_BRIEF.md) §9.

- Route: Gromscheed → Kirchberg, Konrad Adenauer, leave now (`live-now`), planning time 17:51 CEST.
- Build: Release simulator app, `0a54e7d` (plus uncommitted UI-only edits), MobilitéitKit `c4f4b70`.
- Data: GTFS generation 6, walking graph 20260921, stored transfer walks rebuilt first.
- Machine: MacBook Air M4, Xcode 27.0, iPhone 17 simulator (iOS 27.0).
- Command: `python3 Scripts/benchmark_routes.py --app <Release app> --output <dir> --scenarios live-now --warm 1 --cold 1 --maximum-limit-ms 0`

| Sample | Total (ms) | ATP requests | Decoded board bytes |
|---|---:|---:|---:|
| priming (first search after launch) | 10,058 | 27 | 17.9 MB |
| warm (same process) | 7,053 | 19 | 10.7 MB |
| cold (fresh process) | 7,655 | 27 | 17.9 MB |

All three exceed the 5,000 ms gate. n = 1 per sample type on live data, so
treat these as indicative.

## Files

| File | Content |
|---|---|
| `samples.json` | Every sample: spans, passes, rounds, counters, journeys, displayed legs, transport timings |
| `summary.json` | Medians per sample type, as printed by the script |
| `transport-summary.json` | All 73 ATP requests: stop, window, lines, latency, encoded and decoded size (no bodies) |
| `optimisation.json` | Stored transfer-walk table build (11,188 pairs, 8.0 s) |

Raw ATP responses (about 46 MB decoded) are not committed. Record a fresh
capture to replay (see the brief, §12.4).
