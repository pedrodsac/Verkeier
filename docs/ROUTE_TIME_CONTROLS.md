# Route time controls

Verkéier opts into MobiliteitKit's `adjacentTimeWindows` paging policy. The
package's default `departureProfile` policy and explicit departure cursors remain
available to existing consumers.

## Rider behavior

- **Leave now / Leave at:** the same calculation at the resolved departure
  instant. The departure constraint includes any initial access walk.
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
`RouteTimePagingTests` covers accumulation, selection, timeout/retry, empty pages,
superseded responses, GPS stability, arrival ordering, context persistence, and
refinement fallback.

The simulator benchmark adds `earlier`, `arrival-earlier`, and `arrival-later`
scenarios alongside existing `depart`, `arrive`, and `paging` scenarios. It uses
the installed feed and walking graph, recorded ATP transport, and the production
view model, adapter, and rendered route sheet. See
`ROUTE_CALCULATION_PERFORMANCE.md` for the benchmark commands and five-second gate.
