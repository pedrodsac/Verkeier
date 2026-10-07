# Calculated route live tracking — 7 October 2026

Verkéier pins MobiliteitKit `6f0158f27b26dc79c53a40332fcbd0f46702a306`.

## Deterministic checks

- `ROUTING_VERIFY_KERNEL=1 swift test --disable-automatic-resolution --no-parallel`:
  all 192 tests in 24 package suites pass.
- Release iPhone 17 simulator build and the focused app suites
  `RouteRealtimeTrackingTests`, `JourneyPlanningIntegrationTests`, and
  `RouteContinuationTests`: all 18 tests pass.
- Full app suite: 136 tests in 24 suites, 34 existing fixture issues. These
  match the documented full-suite issue count before this change. The failures
  are in the existing presentation, paging and walking fixture assertions;
  no new tracking test fails.

Regressions cover acquisition with zero initial live/search-work allowance,
every connecting vehicle, cancellation and missed-transfer invalidation,
20 stops split into groups despite an earlier failed group, task cancellation,
superseded calculations, accumulated pages, manual selection, repeated forced
refresh, and app generation checks.

## Live verification

A standalone diagnostic executable used the package's production client,
the configured public relay, and a copy of the simulator's installed
`gtfs-20260930-20261212.zip` database. No live network is used in tests.

Origin: Senningerberg, Gromscheed (`000200508004`). Destination:
Kirchberg, Konrad (`000200417019`). Queries ran around 22:17–22:26 Luxembourg
time. The CLI uses package walking estimates; the app separately owns its
measured pedestrian routes. This verifies live acquisition/matching, rather
than rendered app timing.

With production search allowances, all 11 boarding events in four journeys
had reported departure predictions. A second run disabled initial acquisition
and search-work allowances entirely: three journeys contained nine transit
legs, all initially scheduled. `refreshDisplayedRealtime` supplied reported
departure predictions for all nine legs. Seven arrivals were reported and two
remained explicitly estimated. Separate departure-board requests confirmed
predictions were available for every leg's line and scheduled occurrence.

Raw observations: [normal acquisition](live-acquisition.txt) and
[zero initial allowance](live-completion.txt). All times in these raw records
are UTC except the provider's wall-clock prediction strings.

The opt-in rendered benchmark against the previously installed app timed out
waiting for a display callback; no rendered timing claim is made for this run.
