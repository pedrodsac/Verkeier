# Pafendall funicular station connection

The local pedestrian graph routes around the funicular. Before this change,
Rout Bréck-Pafendall tram → Pfaffenthal-Kirchberg train took 513 m / 7 min 33 s
in both directions on the installed graph.

`PafendallFunicularConnection` supplements that graph with a bidirectional
station connection. It applies only between the tram interchange (120 m radius)
and the railway interchange (100 m radius). Walking to and from the terminals
is measured on the installed pedestrian graph, with the usual 1.25 walking
calibration. The ride takes 63 seconds; a separate 60-second product allowance
covers boarding. The combined path is selected only when faster than the
ordinary pedestrian route, or when that pedestrian route is unavailable.

There is no invented GTFS trip, departure timetable, or live status. This is a
continuous interchange connection, matching the treatment in Mobiliteit's
transfer directions. Operating schedules are outside this change's scope.

## Sources

- [CFL: Funicular](https://www.cfl.lu/en-gb/mobilitysolutions/detail/funiculaire):
  links the railway stop and Kirchberg interchange; 63-second ride, 40 m rise.
- [OpenStreetMap track A](https://www.openstreetmap.org/way/466675116):
  geometry continues through ways 272711527, 682347528, 466675117, 542307098,
  466675116 and 682347529. Terminal stop positions are nodes 4268823782
  (lower) and 4268824598 (upper). Retrieved 2026-10-11 from the OSM API.
- [Mobiliteit planner](https://www.mobiliteit.lu/en/plan-a-trip/): the overnight
  Gromscheed → Lorentzweiler comparison includes a 370 m / 5 min transfer
  through the funicular. See `ROUTING_LORENTZWEILER_COMPARISON.md`.

## Search and presentation

MobiliteitKit carries typed `WalkingRouteSegment` values through access, egress,
transfers, live updates and walking refinements. The whole connection consumes
transfer time and the search's conservative movement budget. Published journey
walking totals exclude the ride; connection time, including the boarding
allowance, contributes to in-vehicle time. Train boarding buffers still apply.

The app expands the connection into walk → funicular → walk with its own map
geometry and times. These measured subpaths are not submitted individually as
replacements for the whole native transfer. The legacy geometry-only walking
refiner rejects station rides rather than flattening them into pedestrian paths.

Both the app's measured-path cache and the package's walking cache include the
connection revision, so changes to the connection invalidate old measurements.

## Validation

Offline fixtures cover both directions, exact time accounting, geographic
scope, measured-access evidence, provider metadata, separate itinerary legs,
persistence, and preservation through native live updates. No test uses a live
network or the installed production dataset.

## Installed-graph verification (2026-10-11)

| Direction | Walking access | Funicular including boarding | Walking exit | Total |
|---|---|---|---|---|
| Tram → train | 106 m / 94 s | 225.5 m / 123 s | 39 m / 34 s | **370.5 m / 4 min 11 s** |
| Train → tram | 39 m / 34 s | 225.5 m / 123 s | 106 m / 94 s | **370.5 m / 4 min 11 s** |

Computing the paths took 130 ms forward and 67 ms reverse in Release without
coverage instrumentation. Both directions use the connection instead of the
513 m / 7 min 33 s pedestrian detour.

One overnight timetable replay now returns **325 → T1 → Funicular → RB**, using
Pfaffenthal-Kirchberg's **01:14** train and arriving at Lorentzweiler at **01:25**.
The 212 → T1 → Funicular → RB alternative is also in the unfiltered results.
The replay took 10.720 s: RAPTOR 9.576 s (including walking transfers 6.948 s),
snapshot preparation 447 ms and endpoint routing 216 ms. These overlapping
stages must not be added. This replay used an instrumented Release test host
and empty recorded ATP boards; it is a correctness check, not a comparable
uninstrumented live performance measurement.

All **205 app tests** and **250 package tests** passed. Compact measurements and
route evidence are in
[`verification.json`](benchmarks/pafendall-funicular-2026-10-11/verification.json).
