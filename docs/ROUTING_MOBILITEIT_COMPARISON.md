# Gromscheed 18A → Kirchberg, Konrad Adenauer

Compared on 8 October 2026 using the [mobiliteit.lu journey planner](https://www.mobiliteit.lu/en/plan-a-trip/). The website resolved the origin to **Senningerberg, Gromscheed 18A**. Its first journey walked 388 m to Gromscheed, took the 18:20 Bus 322 to Luxexpo at 18:30, then walked 104 m between platforms 2C and 5 to take Bus 6 at 18:32. Scheduled arrival was 18:39, with a one-minute live delay. Its next alternative was Bus 29 → Bus 16, arriving at 18:46.

The app's existing Gromscheed address regression coordinate is `49.6541071, 6.2296443`; the destination is GTFS stop `000200417019`. The comparison fixes the departure anchor at **2026-10-08 18:11 Europe/Luxembourg**. App calculations use the production view model, adapter, installed GTFS generation 4 and calibrated 21 September pedestrian graph. ATP HTTP transport returns empty recorded boards for reproducible scheduled comparisons. These runs do not claim to reproduce the website's live delay.

| Planner / setting | Useful connection | Scheduled arrival |
|---|---|---|
| mobiliteit.lu | 322 → 6 at Luxexpo | 18:39 (live +1 minute) |
| Verkéier before this change | 29 → 16 at Héienhaff | 18:46:20 |
| Verkéier after this change | 322 → 6 at Luxexpo | **18:39:10**, Tight transfer |
| Verkéier, Avoid tight transfers | 29 → 16 at Héienhaff | 18:46:20 |

The feed's generic same-stop rule at Luxexpo specifies **450 seconds**. Bus 322 arrives at 18:30:05 and Bus 6 departs at 18:32:40: a **155-second** change. The strict router discarded this connection despite the website suggesting it. The app now opts into `allowTightSameStopBusTransfers` for both rider-facing filter settings. This applies only to bus changes at the identical aggregate stop with an unscoped type-2 rule and no declared platform or parent station. At least 120 seconds, the rider minimum and any boarding buffer are still required. The larger feed buffer remains stored as recommendation evidence. **Tight transfer means strictly less than 180 seconds between effective arrival and departure**, regardless of a larger feed recommendation. Exactly 180 seconds is not tight; the Luxexpo 155-second change is tight. The route-card pill appears at the top right only for such tight changes; other statuses do not get a card pill. In-seat continuations are not transfers. The normal two-minute rider minimum is unchanged. Avoid tight transfers raises the rider minimum to three minutes. The normal package initializer and legacy decoding remain strict. Specific trip/route restrictions, different stops, rail/platform changes and wheelchair-required journeys retain full feed rules.

Quality policies preserve comfortable alternatives when a competing journey has a transfer under three minutes. Longer changes can participate in normal route comparisons. Presentation also no longer drops the final result unconditionally: a sole journey, recommendation or fallback remains visible. The best connection improves the scheduled arrival by **7 minutes 10 seconds**. This is corridor evidence, not a claim that every journey beats the official planner.

## Verification

- MobiliteitKit revision `4d5606aa12740338802c3fc7f16f2f54b3e0306c`, published on `codex/short-same-stop-bus-transfers` and pinned by the app.
- The **143-test app suite in 28 suites** succeeds on iPhone 17, Release, coverage disabled: 141 tests pass and two opt-in installed-feed tests are skipped.
- The **26-test focused run in four package suites** succeeds, including installed-feed replay. Fixture cases cover the 119/120-second admission boundary and 179/180-second warning boundary, avoidance filters, scoped and forbidden rules, rail/platform/wheelchair constraints, arrive-by, boarding buffers, live-delay invalidation, legacy decoding and preservation of comfortable alternatives.
- Before the three-minute correction, the full package suite with reference-kernel verification ran **218 tests in 31 suites**. One existing test, `RealtimeBudgetTests.deadlineDuringMatchingKeepsCompletedPatchesAndReportsPartialCoverage`, fails its assumption that a 392-row match must exceed 100 ms; matching completes and returns full coverage. Its requirements were left unchanged. All other tests pass.
- Two-minute-policy rendered cold calculation: **1.36 seconds**; Avoid tight transfers cold calculation: **1.25 seconds**. Each setting has one priming and one fresh-process sample; these are spot checks, not a p95 performance series.

Historical two-minute-policy output: [default](benchmarks/route-quality-2026-10-08/two-minute-default.json), [Avoid tight transfers](benchmarks/route-quality-2026-10-08/two-minute-avoid.json). These traces predate the three-minute cutoff. Current warning and avoidance behavior is covered by the fixture tests above.

Historical output before the earlier two-minute correction: [baseline](benchmarks/route-quality-2026-10-08/baseline.json), [updated](benchmarks/route-quality-2026-10-08/updated.json), [strict filter](benchmarks/route-quality-2026-10-08/avoid-tight-transfers.json).

## Repeat the programmatic comparison

Install current GTFS and pedestrian datasets through the app first; no production archive is bundled or hardcoded. Build Release and pass its app path:

```sh
python3 Scripts/benchmark_routes.py \
  --app /absolute/path/Verkeier.app \
  --output /tmp/verkeier-route-comparison \
  --scenarios depart --time 2026-10-08T18:11:00+02:00 \
  --warm 0 --cold 1

# Repeat with Avoid tight transfers:
python3 Scripts/benchmark_routes.py \
  --app /absolute/path/Verkeier.app \
  --output /tmp/verkeier-route-comparison-strict \
  --scenarios depart --time 2026-10-08T18:11:00+02:00 \
  --avoid-tight-transfers --warm 0 --cold 1
```

The fixed query needs a feed covering 8 October 2026. Use another ISO 8601 instant for a new website comparison. Output includes each journey's departure, arrival, stops, lines and transfer warnings, the unfiltered result list, planning time and selected recommendation.
