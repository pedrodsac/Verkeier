# Evening screenshot regressions

The two screenshots prompted an additional full-profile quality rule in MobiliteitKit `fe43ae9b70aec106d4d0f7929d5c5b82caae04c9`, integrated through the app's remote package pin.

A verified access walk replaces a feeder when it reaches the same remaining vehicle instances and alighting occurrences, leaves home no earlier, arrives no later, and adds at most five minutes of walking. Boarding the first remaining vehicle at another valid occurrence is allowed. Subsequent boarding occurrences must match. Both itineraries must already pass physical, timetable, constraint, accessibility and realtime validation. Different line numbers or headsigns alone never prove equivalence. An explicit less-walking preference preserves a useful feeder.

The rule runs before full-profile publication and again for accumulated session results. Paging and refresh cannot restore a redundant feeder while its valid replacement remains available. Existing exact dominance removes the needless 326 → 311 change when staying aboard the 326 still catches the same 18. A necessary 311 connection remains when the 326 arrives too late.

## Actual installed-feed replay

The replay uses the existing Gromscheed address fixture (49.6541071, 6.2296443), Konrad Adenauer stop `000200417019`, and 1 October 2026 at 20:18 Luxembourg time. The screenshots do not provide precise GPS or live predictions; this is a schedule-only reproduction using the installed generation-3 timetable and real Valhalla pedestrian graph, rather than an exact replay of their live state. The timetable covers 24 September–12 December 2026. The pedestrian dataset is 20260921. No network requests or downloads are used. Replay input SHA-256: timetable `4cc3b13e437f883620cd262fa9ded30b4d1e3d401561040e101c5a41a152bc44`; pedestrian archive `0dd7dd3357e6962b251aaa494063f092cddc50c16e972f20a618e93df4f1600b`.

| Choice | Leave home | Arrival | Total walking | Outcome |
|---|---|---|---|---|
| 326 → 850 → 16 | 20:32:54 | 21:10:10 | 4 min 31 sec | Present in `8bf4741`; removed in `fe43ae9` |
| Walk to Charlys Statioun → same 850 → same 16 | 20:36:18 | 21:10:10 | 8 min 16 sec | Retained; leave 3 min 24 sec later |
| Walk to Breedewues → same 850 → same 16 | 20:36:10 | 21:10:10 | 7 min 24 sec | Retained as another valid boarding choice |

The app replay also verifies that actual trip `24264856` on line 326 directly reaches Gare routière Luxexpo with zero changes. The original needless 326 → 311 → 18 sequence is absent from the evening profile. [Before/after excerpts](replay.txt) preserve the reproduced failure and passing replay.

## Regression coverage

`RoutingWastefulConnectionTests.stayOn326Unless311IsNeededToCatch18` covers staying aboard and a control where changing to 311 is necessary to catch 18. `walkTo850WhenItLeavesHomeLater` covers blocked walking, a later departure, the five-minute additional-walking boundary, excessive walking, earlier home departure, less-walking preference, walking budget, arrive-by, service-day/occurrence identity, paging and refresh. Its feeder and walking choices deliberately board the 850 at different stops.

The offline package gate passes 143 tests in 17 suites with `ROUTING_VERIFY_KERNEL=1`. The Release iPhone 17 app gate passes 49 tests in 11 suites, including `RoutingScreenshotReplayTests.eveningConnectionsAvoidRedundant326` enabled with installed data. Six installed-feed package replay tests also pass in Release without live data. [Gate excerpts](verification.txt).

To repeat the app replay, run `build-for-testing` using the project's simulator command. Set `ROUTING_SCREENSHOT_REPLAY_DATABASE` and `ROUTING_SCREENSHOT_REPLAY_TILES` in the generated `.xctestrun` test target's `EnvironmentVariables` to stable copies of this timetable and its `tiles.tar`. Keep the edited `.xctestrun` beside the original products, then use `xcodebuild -xctestrun <file> -destination 'platform=iOS Simulator,name=iPhone 17' test-without-building -only-testing:VerkeierTests/RoutingScreenshotReplayTests`. Ordinary tests leave this opt-in replay disabled.

## Release rendered performance

All **300 timed operations** across ten scenarios pass the five-second p95 target in every warm/cold group. Ten priming operations are recorded separately and excluded. Worst p95 is **3.882 seconds**; peak simulator resident memory is **811.3 MiB**. The runtime source is app `4ad7a5e` with remote package `fe43ae9`, built in Release with code coverage disabled. Measurements use iPhone 17 / iOS 27.0, the installed feed and pedestrian graph, and the existing recorded ATP fixtures.

Run `python3 Scripts/benchmark_routes.py --app <Release simulator app> --output <directory>` with the default 20 warm and 10 cold samples per scenario. [Summary](summary.json) and [raw samples](samples.jsonl).
