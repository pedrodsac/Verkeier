# Gromscheed 18A → Kirchberg, Konrad Adenauer

Compared on 8 October 2026 using the [mobiliteit.lu journey planner](https://www.mobiliteit.lu/en/plan-a-trip/). The website resolved the origin to **Senningerberg, Gromscheed 18A**. Its first journey walked 388 m to Gromscheed, took the 18:20 Bus 322 to Luxexpo at 18:30, then walked 104 m between platforms 2C and 5 to take Bus 6 at 18:32. Scheduled arrival was 18:39, with a one-minute live delay. Its next alternative was Bus 29 → Bus 16, arriving at 18:46.

The app's existing Gromscheed address regression coordinate is `49.6541071, 6.2296443`; the destination is GTFS stop `000200417019`. The comparison fixes the departure anchor at **2026-10-08 18:11 Europe/Luxembourg**. App calculations use the production view model, adapter, installed GTFS generation 4 and calibrated 21 September pedestrian graph. ATP HTTP transport returns empty recorded boards for reproducible scheduled comparisons. These runs do not claim to reproduce the website's live delay.

| Planner / setting | Useful connection | Scheduled arrival |
|---|---|---|
| mobiliteit.lu | 322 → 6 at Luxexpo | 18:39 (live +1 minute) |
| Verkéier before this change | 29 → 16 at Héienhaff | 18:46:20 |
| Verkéier after this change | 322 → 6 at Luxexpo | **18:39:10**, Tight transfer |
| Verkéier, Avoid tight transfers | 29 → 16 at Héienhaff | 18:46:20 |

The feed's generic same-stop rule at Luxexpo specifies **450 seconds**. Bus 322 arrives at 18:30:05 and Bus 6 departs at 18:32:40: a **155-second** change. The strict router discarded this connection despite the website suggesting it. The app now opts into `allowTightSameStopBusTransfers` when Avoid tight transfers is off. This applies only to bus changes at the identical aggregate stop with an unscoped type-2 rule and no declared platform or parent station. At least 120 seconds, the rider minimum and any boarding buffer are still required. The larger feed buffer remains stored as recommendation evidence and produces a Tight transfer warning. The normal package initializer and legacy decoding remain strict. Specific trip/route restrictions, different stops, rail/platform changes and wheelchair-required journeys retain full feed rules.

Comfortable alternatives survive both the package quality policies and app presentation. The updated run retains 29 → 16 at 18:46:20 and a longer 322 → 6 change at 18:54:20. Presentation also no longer drops the final result unconditionally: a sole journey, recommendation or fallback remains visible. The best connection improves the scheduled arrival by **7 minutes 10 seconds**. This is corridor evidence, not a claim that every journey beats the official planner.

## Verification

- MobiliteitKit revision `362e2a49feb239e2aa3af62107bc7fa2d33f5b83`, published on `codex/short-same-stop-bus-transfers` and pinned by the app.
- All **140 app tests in 27 suites** pass on iPhone 17, Release, coverage disabled.
- **Seven comparison tests in two package suites** pass, including installed-feed replay. Fixture cases cover the 119/120-second boundary, feed-buffer risk, strict filters, scoped and forbidden rules, rail/platform/wheelchair constraints, arrive-by, boarding buffers, live-delay invalidation, legacy decoding and preservation of comfortable alternatives.
- The full package suite with reference-kernel verification runs **217 tests in 31 suites**. One existing test, `RealtimeBudgetTests.deadlineDuringMatchingKeepsCompletedPatchesAndReportsPartialCoverage`, fails its assumption that a 392-row match must exceed 100 ms; matching completes and returns full coverage. Its requirements were left unchanged. All other tests pass.
- Final rendered cold calculation: **1.49 seconds**; strict-filter cold calculation: **1.61 seconds**. Each setting has one priming and one fresh-process sample; these are spot checks, not a p95 performance series.

Raw output: [baseline](benchmarks/route-quality-2026-10-08/baseline.json), [updated](benchmarks/route-quality-2026-10-08/updated.json), [strict filter](benchmarks/route-quality-2026-10-08/avoid-tight-transfers.json).

## Repeat the programmatic comparison

Install current GTFS and pedestrian datasets through the app first; no production archive is bundled or hardcoded. Build Release and pass its app path:

```sh
python3 Scripts/benchmark_routes.py \
  --app /absolute/path/Verkeier.app \
  --output /tmp/verkeier-route-comparison \
  --scenarios depart --time 2026-10-08T18:11:00+02:00 \
  --warm 0 --cold 1

# Repeat with the conservative feed buffers:
python3 Scripts/benchmark_routes.py \
  --app /absolute/path/Verkeier.app \
  --output /tmp/verkeier-route-comparison-strict \
  --scenarios depart --time 2026-10-08T18:11:00+02:00 \
  --avoid-tight-transfers --warm 0 --cold 1
```

The fixed query needs a feed covering 8 October 2026. Use another ISO 8601 instant for a new website comparison. Output includes each journey's departure, arrival, stops, lines and transfer warnings, the unfiltered result list, planning time and selected recommendation.
