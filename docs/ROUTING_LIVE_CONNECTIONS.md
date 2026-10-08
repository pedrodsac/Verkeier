# Live updates for connecting trips

Live observations participate in the initial route calculation. The router uses
a scheduled scan to prioritize boarding requests, discovers other outgoing lines
that can become catchable through delays, then runs RAPTOR with that evidence
before returning the first result. A transfer that is impossible on the timetable
can therefore appear immediately when its connecting vehicle is late.

Selected itinerary stops receive acquisition priority. An optimistic, destination-aware
frontier identifies alternative outgoing lines before fetching; their targets are
merged with the itinerary targets in one concurrent batch. A selected-line request
does not mark the whole interchange as explored. The discovery limit includes
itinerary stops, while permitting other lines at those stops to be checked. Nearby
boardings on an already requested vehicle reuse its passlist; long rides retain
later boarding checks before forecast propagation expires.

## Acquiring initial live evidence

The app uses an eight-second shared live-acquisition allowance and up to sixteen
concurrent board requests. The former 2.5-second cutoff could cancel available
forecasts before they reached the calculation. An 8 October board request took
7.4 seconds; the initial calculation now allows that response time. Slow responses
can exceed the historical five-second rendered target. Boards filter to selected
and alternative lines at each stop, retaining unlimited journeys and full passlists.
A sampled line-21 board fell from approximately 1.3 MB to 100 KB with
the API's line filter; tram filtering was also checked against live responses.

RAPTOR builds candidates before requesting their boarding occurrences, including
walking and stay-aboard connections. These targets include the permitted two-hour
delay range and stay within the current route search horizon. Discovery planning
is limited to 250 ms, leaving the rest of the shared deadline for HTTP, decoding,
matching and merging. Discovery boards use the same concurrency as itinerary boards.

Live evidence triggers another RAPTOR scan so delays, cancellations and transfer
restrictions affect feasibility and ranking. Refinement is limited to two waves;
a final scan applies the last acquired evidence. Intermediate-stop presentation
events are built only for retained journeys, avoiding that work for discarded
profile candidates. Search coverage, walking validation and quality selection
remain intact. Quality-envelope selection first applies cheap necessary timing,
walking, transfer, mode and accessibility bounds before the existing predicates;
a differential fixture checks equivalence to exhaustive selection.

CPU elapsed time cannot suppress either required acquisition pass. A positive
legacy search-work allowance previously skipped live checks for vehicles newly
selected after the first overlay. Those vehicles now use the remaining shared
acquisition budget before publication. Explicit zero still disables acquisition
for callers that request it; the app no longer supplies that legacy allowance.

Matching memoizes timestamp parsing, normalized identities and service-day
anchors within each batch. Repeated vehicle passlists reuse those pure
conversions. Full timetable ambiguity, DST rejection, observation age and
forecast propagation remain part of matching. The caches are bounded and cleared
between batches; they cannot prolong a forecast's freshness.

Shared caching reuses compatible coverage and preserves each observation's
original timestamp. The coordinator matches all forecasts on requested lines,
including alternative vehicles that may become useful after delays; it does not
limit patch construction to the original scheduled winners. A complete unrestricted board can satisfy a filtered request;
a filtered response cannot supply unrestricted board coverage. Explicit refresh
bypasses completed evidence. Unavailable, ambiguous, contradictory or expired
reports retain honest scheduled or partial coverage.

The app pins MobiliteitKit revision
`353a15755b9c98c5e8f23c80aa1124c35bf010f3`.

## Tracking calculated routes

The initial search allowance does not end live acquisition. Once route results
are visible, the app immediately calls `refreshDisplayedRealtime` through its
injected `RouteRealtimeRefreshing` service. The package checks every transit
boarding occurrence in the accumulated session, including connecting vehicles
and previously loaded pages. Groups of eight boarding stops each receive their
own eight-second allowance, so a failed or slow earlier group cannot consume
the opportunity of later stops. This work runs after route publication.

The first check reuses fresh board coverage. Subsequent checks request fresh
reports every 45 seconds while the directions or timeline is visible and the
app is active. Changing endpoints, starting another calculation or page,
leaving the route screen, or backgrounding the app cancels the tracking task.
Generation checks reject late reports from superseded requests.

The package applies matched trip-instance updates to existing journeys, retaining
measured walking geometry, page boundaries and per-journey validation contexts.
It rechecks feasibility and ranking, removes cancellations and missed transfers,
and returns an authoritative snapshot. The app preserves a usable manual
selection or selects the package recommendation. Predictions keep their original
observation timestamps; unavailable or expired evidence remains scheduled.

[7 October validation](benchmarks/route-live-tracking-2026-10-07/validation.md)
includes all 192 package tests, 18 focused app tests, and a live query that
upgraded all nine initially scheduled transit legs to reported departure
predictions with the initial acquisition allowance set to zero.

## Correctness verification

The 8 October regression uses three different lines. The first reaches the
interchange at 08:10 on the timetable; line 202 leaves at 08:08, so only a slower
line 203 is initially viable. Live observations put the first arrival at 08:11
and line 202's departure at 08:14. The first returned result must contain and
recommend that connection, with reported timing on both vehicles. The mock
honors API line filters, so a line-203 request cannot accidentally supply line 202.
Both departure and arrive-by searches are checked with an available fallback,
a stalled fallback board, no scheduled route, an exhausted positive CPU allowance,
and 1.4-second live responses. The app adapter checks both time modes with cached
and forced acquisition before any tracking refresh. All 194 package tests in
26 suites pass with kernel verification enabled. An additional three-vehicle
fixture with a missing discovery board verifies that the newly selected third
vehicle gets its live departure and arrival before publication, even after a
positive CPU allowance is exhausted.
The Release simulator build passes all 19 focused app tests in four suites.
See [8 October validation](benchmarks/initial-live-routing-2026-10-08/validation.md).

On 4 October 2026, all 187 package tests in 23 suites passed with
`ROUTING_VERIFY_KERNEL=1 swift test --disable-automatic-resolution --no-parallel`.
Regressions cover live data on all three connecting vehicles, acquisition priority
over stalled discovery branches for both departure and arrive-by searches,
cancellation and missed-connection removal, cache reuse and refresh, timestamp-free
merging, full-timetable ambiguity with targeted matching, filtered-board cache
isolation, retained intermediate-stop predictions, and sixteen trip boards
completing within one shared deadline. Other regressions cover backward-compatible
work-budget decoding, zero remaining acquisition time with a complete static
search, and ATP minute precision overlapping a preceding unreported GTFS stop
by at most 90 seconds. Such constrained events remain estimated; larger conflicts
and contradictory direct reports remain rejected.

The Release simulator build and all 11 journey-planning integration and
continuation tests pass. Earlier full-app runs reported 34 fixture issues; an
isolated project with the previous `f198548` pin reproduced all 34 issue locations
and counts. Those issues were outside the router change.

## Rendered timing verification

[Validation and raw measurements](benchmarks/route-live-connections-2026-10-04/validation.md)
record the 112-operation full matrix (maximum 3.43 seconds) and two twelve-operation
live series plus eight final affected-path checks: 144 operations total, all below
five seconds (maximum 3.96 seconds), including priming and cold processes. The final
pin's departure/reverse series applied all 68 unambiguous available predictions
in initial-result comparisons. Final arrive-by comparison was blocked by the
provider's hourly quota; the earlier live arrival run passed the timing boundary,
and the resulting minute-precision fix passes offline regressions. The benchmark
now rejects any individual operation at or above five seconds, including priming.

## Earlier diagnostic

The earlier sequential eight-second acquisition approach applied all 40 available
predictions in four sampled live calculations but took 10.22–12.30 seconds.
It failed the then-required five-second boundary. The 8 October calculation uses
one concurrent batch for selected and alternative lines and prioritizes initial
live feasibility over cancelling forecasts to meet that earlier boundary.

## Reproduce

Build Release for the iPhone 17 simulator with coverage disabled. Install current
GTFS and walking graphs through the ordinary app, then run the production route
sheet harness. Its timer includes preparation, acquisition, routing, mapping,
publication, idle loading state, and two rendered display callbacks. Dataset
downloads and later decorative geometry refinement are excluded.

```sh
python3 Scripts/benchmark_routes.py \
  --app /path/to/Release-iphonesimulator/Verkeier.app \
  --output /tmp/verkeier-route-performance \
  --scenarios depart reverse coordinates arrive exact rural paging earlier \
    arrival-earlier arrival-later refresh recorded-live deadline-arrive cached \
  --warm 5 --cold 2

python3 Scripts/benchmark_routes.py \
  --app /path/to/Release-iphonesimulator/Verkeier.app \
  --output /tmp/verkeier-live-performance \
  --scenarios live-now live-reverse live-arrive --warm 2 --cold 1
```
