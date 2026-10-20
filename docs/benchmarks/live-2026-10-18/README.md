# Live re-baseline: one route, 3 rounds (18 October 2026, Sunday)

Live `live-now` searches after steps 0–2 of
[ROUTING_SPEED_PLAN.md](../../ROUTING_SPEED_PLAN.md), on a quiet machine.

- Route: Gromscheed → Kirchberg, Konrad Adenauer, leave now (`live-now`), planning
  times 18:32–18:34 CEST on a **Sunday**. Sunday service gives lighter inputs than
  the Thursday 17:51 baseline in `../live-baseline-2026-10-15/`: 6.4–6.6 MB of
  boards per search instead of 17.9 MB, and scan passes of 130–184 ms instead of
  about 290 ms. Compare the gate verdict with a weekday run, not with this one.
- Build: Release simulator app at `60b0c97` (plus uncommitted UI-only edits),
  MobilitéitKit `1779b82`, packages cloned fresh from the pinned revision.
- Machine: MacBook Air M4, iPhone 17 simulator, mains power, Low Power Mode off,
  no other build or benchmark running. Transfer-walk build (CPU canary):
  2,021 / 1,878 / 1,937 ms.
- Command, per round: `python3 Scripts/benchmark_routes.py --app <Release app>
  --output <dir> --scenarios live-now --warm 1 --cold 1 --maximum-limit-ms 0
  --request-budget 120`
- ATP requests: 81 per round (27 per sample), 243 in all.

| Sample, ms | Round 1 | Round 2 | Round 3 | Median |
|---|---:|---:|---:|---:|
| Priming | **5,657** | 3,161 | 2,778 | 3,161 |
| Warm | 2,110 | 1,905 | 2,407 | 2,110 |
| Cold | 2,961 | 2,183 | 3,697 | 2,961 |

Every sample returned the same 6 engine journeys and the same recommendation.
Every sample ran two authoritative passes.

## Files

| File | Content |
|---|---|
| `round-N/samples.json` | Every sample: spans, passes, rounds, counters, journeys, per-request URLSession timestamps |
| `round-N/summary.json` | Medians per sample type, as printed by the script |
| `round-N/transport.json` | Metadata of every captured ATP response (no bodies) |
| `round-N/optimisation.json` | Transfer-walk table build (the CPU canary) |

The raw bodies and bike snapshots are outside git, in
`~/Developer/Verkeier-captures/live-2026-10-18/round-N/`. The replay loader keeps
the first body per query in file-name order, mixing the three samples'
latencies, so a replay of one round does not reproduce one sample's network
timing.
