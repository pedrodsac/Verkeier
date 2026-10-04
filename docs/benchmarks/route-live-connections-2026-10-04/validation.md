# Connecting-trip live data and five-second search gate — 4 October 2026

## Source and setup

The app pins MobiliteitKit `60af526ac2d6f87e39fc02565c771164f37adf55`.
The router-work changes were measured first at `cdd81887d2c9ee11626955503d5fdaeb4fdf1515`;
the final pin adds the minute-precision correction for unreported preceding stops.
The package branch `codex/live-connecting-trips` also contains a later documentation-only commit.

Release, coverage disabled, no debugger or concurrent profiling; iPhone 17 / iOS 27
simulator on the M4 MacBook Air. GTFS and walking datasets were already installed
through the ordinary app. Cold samples use a new app process, with OS filesystem
caches potentially warm. The benchmark charges deferred timetable preparation to
the first operation. These are simulator measurements, not a physical-device bound.

The timer starts in the production view-model operation and ends after the route
sheet has committed its complete initial snapshot and idle loading state, followed
by two display callbacks. It includes readiness, endpoints, live acquisition,
routing, mapping and rendering. Dataset download, unresolved location, later
geometry refinement and the comparison-board requests are outside this gate.

## Work and coverage policy

The live allowance is 2,500 ms, shared across at most two completion waves. Sixteen
itinerary boards can run concurrently, with four broad-discovery slots and a
one-eighth discovery allowance. Boards retain unlimited journeys and full
passlists, filtered to needed lines. All forecasts returned on those lines are
matched, so replacement vehicles can reuse evidence. Each itinerary transit leg
receives priority, including walking and in-seat connections.

A 4,100 ms generation-work allowance accounts for endpoint work and reserves
last-scan time plus 5% and 100 ms before another acquisition wave. It limits live
waiting adaptively and always leaves a full scan to apply acquired reports.
Scheduled coverage is unchanged: three hours initially for departure, 24 hours
for arrive-by/paging, three transfers and 48 labels per profile. Intermediate-stop
presentation events are materialized after selection; quality-envelope pruning
preserves the original predicates and is differential-tested.

ATP minute precision can put a valid boarding report before an unreported
preceding GTFS event. Overlaps of at most 90 seconds constrain that unreported
event, marking it estimated with the report's observation time. Conflicting direct
reports and larger overlaps remain rejected. The final live series verifies this
against the line-322 report that exposed it.

## Verification

The package full suite passed 187 tests in 23 suites with kernel verification.
The final five-second timestamp-overlap fixture and its rejection cases then passed in the
10-test occurrence suite. The pinned Release app build and all 11 integration
and continuation tests passed. Earlier full-app fixture failures (34 issues) were
also reproduced at the previous package pin; those are not represented as passing
in this report.

The benchmark now rejects any sample at or above 5,000 ms, including priming.
A manual boundary check confirmed 4,999 ms passes and 5,000/5,001 ms fail.
The former `--p95-limit-ms` flag remains an alias for `--maximum-limit-ms`;
a zero limit remains available for separate Debug audits.

## Evidence files

- `matrix-*`: 112 operations across fourteen scenarios at `cdd8188`, including all
  priming operations. All were below five seconds; maximum 3,429.362 ms. Scenarios:
  depart, reverse, coordinates, arrive, exact, rural, paging, earlier,
  arrival-earlier, arrival-later, refresh, recorded-live, deadline-arrive, cached.
  Compatible cached samples issued zero board requests.
- `final-live-*`: twelve operations at `60af526`, including priming; maximum
  3,767.007 ms. Departure/reverse initial results applied all 68 unambiguous
  available comparison-board predictions. After compatible cache reuse, all 71
  available predictions were applied. Counts include repeated warm calculations;
  they are per-displayed-leg comparisons, not unique vehicles. These runs acquired
  605–833 predicted events. The provider hit its hourly HTTP 429 quota during the
  final arrive-by series, so those four samples are a timing/availability check
  with zero acquired predictions; they do not establish final-pin live arrival
  coverage. The preceding arrival series acquired 260–351 predictions and finished
  below 3,956.023 ms, then the minute-precision regression was fixed and fixture-tested.
- `final-affected-*`: eight final-pin operations covering recorded live matching
  and the full silent-network deadline, including priming. All passed; maximum
  3,416.582 ms. The recorded scenario retains matched
  predictions and the silent scenario renders the complete scheduled result.
- `prior-live-*`: twelve operations at `cdd8188`; maximum 3,956.023 ms. This timing
  pass exposed the line-322 minute-precision rejection and is retained as the
  diagnostic preceding the final correction.

Warm live searches deliberately force refresh. Fresh cached reroutes and departure
board comparisons are recorded separately; they are not substituted for uncached
search timings. Comparison boards are acquired after publication, so newly
available reports can differ from the evidence available during a timed search.

## Reproduce

```sh
xcodebuild -project Verkeier.xcodeproj -scheme Verkeier \
  -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17' \
  ENABLE_CODE_COVERAGE=NO build

python3 Scripts/benchmark_routes.py \
  --app /absolute/path/to/Release-iphonesimulator/Verkeier.app \
  --output /tmp/verkeier-routing-matrix \
  --scenarios depart reverse coordinates arrive exact rural paging earlier \
    arrival-earlier arrival-later refresh recorded-live deadline-arrive cached \
  --warm 5 --cold 2

python3 Scripts/benchmark_routes.py \
  --app /absolute/path/to/Release-iphonesimulator/Verkeier.app \
  --output /tmp/verkeier-routing-live \
  --scenarios live-now live-reverse live-arrive --warm 2 --cold 1
```
