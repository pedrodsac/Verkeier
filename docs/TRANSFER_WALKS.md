# Stored transfer walks and route preparation

Every transit search measures the walks between nearby stops (RAPTOR walking
transfers). Computing them with Valhalla in every fresh process dominated the
first search: about 1.8 s of a 3.9 s live search on a simulator, and 4.9 s for
3,723 routes on an iPhone 13. The whole country has only about 11,200 directed
transfer pairs, so Verkéier measures them once, stores them on disk, and serves
them from there.

**Results are unchanged.** The table is a memo of one deterministic computation.
It never alters which walk a search sees, only how fast it is produced.

## What is stored

For every pair in `TransitRouter.transferWalkingRequests()` (MobiliteitKit: the
pairs RAPTOR can request) the table holds the outcome of

`LocalFirstWalkingRouter.uncachedRoute(from, to, preferShortSearch: true)`

for unnamed points: a calibrated pedestrian route (distance, duration, polyline,
source) or a deterministic "no route". Doubles are stored as raw bit patterns, so
decoded values are bit-identical.

Never stored (always computed live):

- Pafendall interchange pairs (`PafendallFunicularConnection.terminals != nil`),
  whose result depends on `CLLocation` distances and point names.
- Any route with segments or a source other than `.localOSM`.
- Any failure that is not request-determined. Only `WalkingRoutingError.noRoute` /
  `.invalidResponse`, `DecodingError` and Valhalla codes 154, 170, 171, 441 and 442
  count as "no route" (`TransferWalkErrorClassifier`). Cancellation, a missing
  dataset, router creation errors and wrapper failures abort the build and write
  nothing.

File: `Application Support/Routing/transfer-walks/transfer-walks.bin` (about 6 MB).
Custom little-endian format v1: header (graph and timetable identity), a sorted
48-byte index, contiguous payloads, and a SHA-256 footer. Loaded memory-mapped and
fully validated; a corrupt file is discarded (only if it is still the file that
failed) and rebuilt.

## Why results stay identical

The lookup happens inside the calculate closure of `MeasuredWalkingRouteCache`
(`LocalFirstWalkingRouter.calculatedRoute`), so cache keys, flights, eviction and
the short-versus-full-search race between callers are untouched. It is consulted
only when `preferShortSearch` is true (the RAPTOR batch path) and both points are
nameless, and only when the table's graph identity equals the dataset captured for
the batch. A hit still checks cancellation. Everything else computes live.

MobiliteitKit's own `WalkingRouteCache` (including `correct()` overrides from
walking refinement) sits above the app and is unaffected.

## Identity

- **Graph identity** (`TransferWalkGraphIdentity`): algorithm revision, dataset
  version, tile archive SHA-256, Valhalla core commit and mobile version, the
  Pafendall revision and the calibration multiplier. Portable across backups, unlike
  the inode-based `RoutingDataset.revision`. A table for another graph is ignored.
- **Timetable identity**: the active GTFS database filename. It decides coverage
  only. Walks depend on the walking map, not the timetable, so a new timetable only
  needs the pairs that did not exist before.

**Bump `TransferWalkGraphIdentity.algorithmRevision`** whenever a result-affecting
walking change lands: `ShortWalkingRouteSearch` thresholds, `WalkingPathRequest` /
`WalkingPathResponse`, `ValhallaWalkingRouter.decodePolyline6`, `uncachedRoute`,
the calibration, or the valhalla-mobile / openapi-models pins.
`TransferWalkAlgorithmRevisionTests` pins a digest of fixed pairs on the bundled
tiles and fails with this instruction when it moves.

## Launch flow

`RoutingOptimisationLaunchCheck` runs synchronously in `VerkéierApp.init` and reads
only small files (bundled manifest, active manifest, table header, GTFS metadata).
It never opens SQLite, hashes the table, or waits for the walking graph install.

| Stored table | Result |
|---|---|
| None, or for another graph | full build (waits for a timetable on the very first run) |
| Same graph, other timetable | incremental build: only new pairs are computed |
| Same graph and timetable | nothing |
| Two unfinished attempts for this target | nothing (crash-loop guard) |

A bundled walking graph that is about to be installed counts as the expected graph;
if its installation fails it is remembered and no longer expected, so a failed
install cannot cause the screen on every launch.

While a build runs, `LaunchGateView` replaces the map with a full-screen, non-
dismissable linear progress bar. It shows a launch-storyboard placeholder for the
first 400 ms so near-instant runs never flash. It never interrupts onboarding: on a
brand-new install the build starts as soon as the first timetable installs, and the
screen appears only after the onboarding cover has dismissed (and not at all if the
work has finished by then). A failure shows once with a Continue button and is
retried on the next launch. Deep links and Spotlight results received while the map
is unmounted are stored as intent handoffs and replayed by the map.

`TransferWalkOptimisationService` runs one build at a time (a second caller joins
it), reports whole-percent progress, stops a build that makes no progress for 60 s,
and holds a background-task assertion that never cancels the run.

## Switches (debug, simulator and benchmark builds)

- `ROUTING_TRANSFER_WALKS=0` (or `--disable-transfer-walks`): ignore the table.
- `ROUTING_TRANSFER_WALKS=verify`: recompute every stored walk live and fail on a
  mismatch.
- `ROUTING_TRANSFER_WALKS_DIRECTORY`: use another store directory.
- The test host always runs with the table off and never touches the real store.

`Scripts/benchmark_routes.py --transfer-walks on|off|verify` builds the table in
its own process before the measured fresh-process samples.

## Verification

- `TransferWalkEquivalenceTests`: real bundled tiles, about 30 pairs including the funicular, no-route and identical-endpoint cases; hit counts asserted.
- `TransferWalkAlgorithmRevisionTests`: golden digest tripwire (see Identity).
- `TransferWalkRealFeedEquivalenceTests`: all ~11,200 pairs of an installed timetable (opt-in via `ROUTING_TEST_FEED_DIR`).
- Three-arm Release benchmark: [benchmarks/transfer-walks-2026-10-14](benchmarks/transfer-walks-2026-10-14/README.md).

## Known limitation: funicular ride length

The Pafendall ride length comes from `CLLocation.distance`, and that value shifts by a few centimetres once native Valhalla routing has run in the
process, with or without the table. It is a pre-existing history dependence in the live computation. Funicular pairs are never stored, so the table does
not touch it, but two runs can differ in that one distance. Tests therefore compare funicular pairs with a 0.1 m tolerance on that distance and require
everything else to be equal.
