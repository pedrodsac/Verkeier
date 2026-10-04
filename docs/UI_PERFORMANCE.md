# UI performance

The October 4, 2026 performance work initially addressed launch work and map
updates. A subsequent physical-device recording identified the continuing
scrolling freeze in the departure board, including when it was retained behind
another tab.

## Departure-board freeze

A 32.82-second SwiftUI recording attached to Verkéier on an iPhone 13 running
iOS 27.0.1 captured ten main-thread hangs. The longest lasted 6.19 seconds;
combined hang duration was 30.31 seconds. The main thread was running throughout
the sampled hang windows. `StopDetailView` had twelve body updates averaging
2,246 ms, and `TransitSheetDestinationView` had twelve averaging 672 ms.
Time Profiler stacks show Foundation string folding and locale-cache work
called from the app's list-content construction. The installed app's UUID did
not match the subsequently rebuilt local dSYM, so app-address symbolication
was not used to infer function names.

`StopDetailPresentationModel.board` previously rebuilt a board on every getter.
The list and toolbar accessed its platforms and departures repeatedly. Each
rebuild scanned previously accepted rows and normalized line/destination strings
for every pair, including for hidden navigation destinations invalidated by
shared presentation changes.

The replacement prepares immutable board arrays once and caches them in
`TransitMapViewModel` against explicit data, stop, route, source, line/platform,
and locale inputs. Getter reads no longer normalize, deduplicate, or sort.
Deduplication indexes accepted IDs and normalized journeys in minute buckets,
preserving first-row selection and the inclusive one-minute tolerance without
a pairwise scan. The cache is excluded from Observation, so populating it does
not invalidate the view tree. Timetable source selection and freshness rules
are unchanged.

Baseline trace: `/tmp/verkeier-short-baseline.trace`; parsed analysis:
`/tmp/verkeier-short-baseline-analysis.json`. The earlier device recording lost
its samples when the connection dropped and was excluded from evidence.

Validation: the Release simulator test action passed (108 passed, one optional
test skipped). Six new tests cover journey tolerance and ID handling, unsorted
feed equivalence, stable prediction ordering, platform/line filtering, and
cache invalidation. The signed Release device build also passed and was
installed on the same iPhone. A comparison recording is pending: iOS refused
the launch because the phone was locked, and a subsequent launch attempt timed
out. The fix's device frame pacing has not yet been verified.

## Changes

- `MobiliteitGTFSService` now reads installed metadata, removes inactive
  databases, and opens SQLite during its first actor-isolated operation. Its
  initializer only stores paths and dependencies. Every offline query can
  initialize the installed feed without a network refresh.
- `JCDecauxBikeShareStore` reads and decodes cached stations on its actor rather
  than during app dependency construction. Cached availability remains usable.
- `TransitMapLayer` owns map-specific Observation reads separately from the
  screen. Search, departure, and sheet state do not become map render inputs.
- `MapContainerView` compares value inputs before allocating annotation objects,
  skips redundant layout requests, and synchronizes only changed map layers.
  Camera-only changes do not rebuild pins. Payload equality includes stop and
  station metadata so stable identifiers cannot hide a changed pin.
- GTFS/live stop matching indexes normalized live names once rather than folding
  names in every pairwise comparison. Unchanged results are not republished.
- Changed annotation coordinates and titles send KVO notifications to MapKit;
  unchanged payloads retain their annotation instances without notifications.

## Evidence

An isolated optimized host benchmark ran the old and new matching function
bodies against the same synthetic input: 500 GTFS stops, 50 live stops, 50
name/location matches, and 30 warmed samples. Output arrays matched exactly.

| Measurement | Before | After |
| --- | ---: | ---: |
| Median stop-matching time on the host Mac | 46.67 ms | 0.65 ms |
| Annotation allocations per unchanged representable update with 500 stops | 500 | 0 |

The allocation row follows the update paths in source. The timing row measures
only matching, not launch duration or device animation performance.

A 20.7-second Release launch capture on the iPhone 17 / iOS 27 simulator showed
`pread` and `sqlite3VdbeExec` samples on background threads. The app subsequently
rendered the map, clustered stops, cached bike stations, and bottom sheet. The
Time Profiler recording had an Instruments warning about one table without a
known input source; it supplies no reliable SwiftUI cause graph or frame-hitch
comparison. The trace and parsed output were kept in `/tmp/verkeier-ui-lag-launch.trace`
and `/tmp/verkeier-ui-lag-launch-analysis.json` during this session.

Validation: simulator build passed; the Release test action passed 103 tests in
20 suites. New regressions cover deferred disk access, first-query offline feed
loading, active-generation preservation, cached bike availability, normalized
name/distance matching, camera commands, pin appearance, and changed annotation
payloads.

## Device verification

Use the scheme's Release Profile action and the SwiftUI Instruments template on
a physical iPhone. Repeat launch with an installed feed, bottom-sheet dragging,
map panning, search typing, and departure-list scrolling. Compare long main-thread
updates and animation hitches. The simulator smoke check does not establish the
before/after frame rate of those interactions; native simulator gesture control
was unavailable in this session.
