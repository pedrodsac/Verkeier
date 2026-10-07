# Live updates for connecting trips

The router requests live data for every transit vehicle in the candidate page
before broad discovery. This prevents unrelated branches from consuming the
acquisition deadline before a second or third vehicle is checked.

## Keeping the complete search below five seconds

The app uses a 2.5-second shared live-acquisition allowance and up to sixteen
concurrent itinerary-board requests. Boards filter to the actual lines needed
at each stop, retaining unlimited journeys and full passlists. This removes the
queue and large unrelated responses that made the earlier eight-second approach
too slow. A sampled line-21 board fell from approximately 1.3 MB to 100 KB with
the API's line filter; tram filtering was also checked against live responses.

RAPTOR builds candidates before requesting their boarding occurrences, including
walking and stay-aboard connections. These targets include the permitted two-hour
delay range and stay within the current route search horizon. Four requests can
run concurrently during broad discovery; its allowance is capped at one eighth
of the live budget. Connecting vehicles receive acquisition priority.

Live evidence triggers another RAPTOR scan so delays, cancellations and transfer
restrictions affect feasibility and ranking. Refinement is limited to two waves;
a final scan applies the last acquired evidence. Intermediate-stop presentation
events are built only for retained journeys, avoiding that work for discarded
profile candidates. Search coverage, walking validation and quality selection
remain intact. Quality-envelope selection first applies cheap necessary timing,
walking, transfer, mode and accessibility bounds before the existing predicates;
a differential fixture checks equivalence to exhaustive selection.

The app also supplies a 4.1-second search-work allowance. Before another live
wave, the router reserves the last measured scan/materialization time plus 5%
and 100 ms for a full final scan, then limits acquisition to the remaining time.
Adjacent windows subtract elapsed work from that same allowance. Endpoint work
is included; readiness, mapping and rendering sit outside it; the complete rendered
operation is verified independently. This is an adaptive acquisition limit,
not a hard CPU timeout, and does not truncate the scheduled search.

Shared caching reuses compatible coverage and preserves each observation's
original timestamp. The coordinator matches all forecasts on requested lines,
including alternative vehicles that may become useful after delays; it does not
limit patch construction to the original scheduled winners. A complete unrestricted board can satisfy a filtered request;
a filtered response cannot supply unrestricted board coverage. Explicit refresh
bypasses completed evidence. Unavailable, ambiguous, contradictory or expired
reports retain honest scheduled or partial coverage.

The app pins MobiliteitKit revision
`6f0158f27b26dc79c53a40332fcbd0f46702a306`.

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

The superseded eight-second acquisition allowance applied all 40 available
predictions in four sampled live calculations but took 10.22–12.30 seconds.
It failed the required five-second boundary. That allowance has been removed.

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
