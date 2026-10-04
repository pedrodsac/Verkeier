# Route time controls

Verkéier opts into MobiliteitKit's `adjacentTimeWindows` paging policy. The
package's default `departureProfile` policy and explicit departure cursors remain
available to existing consumers.

## Rider behavior

- **Leave now / Leave at:** the same calculation at the resolved departure
  instant. The departure constraint includes any initial access walk.
  Picker selections use the displayed minute rather than retained hidden seconds;
  a selection in the current minute is clamped to the actual current instant.
- **Arrive by:** door-to-door arrival must meet the selected deadline; the
  recommended journey has the latest feasible departure.
- **Earlier / Later:** add up to five useful transit alternatives, preserving
  the current valid selection. Departure searches browse departure boundaries;
  arrive-by searches browse destination-arrival boundaries. Later arrivals can
  exceed the originally chosen deadline and can depart before the previous
  arrival boundary.
- Earlier can show past timetable journeys. Missed services retain their status;
  a wholly historical search uses schedules rather than historical predictions.
- Adjacent searches start with three-hour windows and expand across gaps up to
  the existing 24-hour horizon. Stable journey IDs resolve equal-time boundaries.
  A partial page leaves browsing available; an exhausted search disables its
  direction and announces that no additional routes were found.

The displayed range identifies the active browsing window. The original chosen
time stays unchanged, so Refresh Routes starts a fresh search at that time.

## Ownership and failure handling

MobiliteitKit owns window selection, accumulation, route quality, and each
journey's validation context. Bounds are applied before candidate representatives
and dominance. Walking refinements and replacement searches use the originating
page's context, not the initial request's deadline.

The app maps that context onto each `RouteOption`, including replacement and
persistence paths. Paging uses the normal calculation deadline, preserves results
on failure, permits retry, and rejects superseded responses. Changing endpoints,
filters, or travel time clears the old generation. A current-location origin is
frozen for the browsing session so GPS movement cannot reset the package session.

## Verification

`AdjacentJourneyPagingTests` covers resolved-time equivalence, normal forward
suggestions, historical routes, moving arrival windows, latest feasible
departures, access/egress, per-page walking refinement, sparse timetables,
equal-time boundaries, repeated alternating pages, and overnight service dates.
`RouteTimePagingTests` covers picker minute precision, accumulation, selection, timeout/retry, empty pages,
superseded responses, GPS stability, arrival ordering, context persistence, and
refinement fallback.

Historical page searches retain realtime evidence for previously loaded journeys,
so their freshness and cancellation checks remain active while browsing the past.

The simulator benchmark adds `earlier`, `arrival-earlier`, and `arrival-later`
scenarios alongside existing `depart`, `arrive`, and `paging` scenarios. It uses
the installed feed and walking graph, recorded ATP transport, and the production
view model, adapter, and rendered route sheet. See
`ROUTE_CALCULATION_PERFORMANCE.md` for the benchmark commands and five-second gate.

## Results — 4 October 2026

The final iPhone 17 / iOS 27 Release simulator run passed the five-second
rendered-result gate for all six scenarios: 20 warm and 10 fresh-process samples
each, plus one excluded priming operation. All 180 timed operations stayed below
2.18 seconds. Full results are in
[`summary.json`](benchmarks/route-time-controls-2026-10-04/summary.json).

| Scenario | Warm p95 | Cold p95 |
|---|---:|---:|
| Leave at | 1.50 s | 2.08 s |
| Arrive by | 1.56 s | 2.18 s |
| Later | 0.59 s | 0.44 s |
| Earlier | 1.17 s | 1.24 s |
| Earlier arrivals | 1.04 s | 1.20 s |
| Later arrivals | 2.06 s | 1.19 s |

The benchmark re-primes an exhausted paging direction outside the timed
operation, matching the initial-page prerequisite of the existing paging
benchmark. An initial small audit recorded a 6.27-second cold departure; the
final 20/10 series ran after builds and tests were complete and passed throughout.
These are simulator measurements, not physical-device guarantees.

Validation: 119 app tests passed, 176 package tests passed with
`ROUTING_VERIFY_KERNEL=1`, and the Release build succeeded. The app pins
MobiliteitKit revision `f19854837622e3ce702108263c89bd3f91edbf46`.
