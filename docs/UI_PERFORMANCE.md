# UI performance

The October 4, 2026 performance pass addresses launch work and unnecessary map
updates. These are code-backed causes of lag; device frame pacing still needs
measurement against the user's exact interactions.

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
