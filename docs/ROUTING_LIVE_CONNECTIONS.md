# Live updates for connecting trips

The router now requests live data for every transit vehicle in the candidate
page before broad discovery. Previously, discovery could spend its entire budget
on unrelated stops, leaving a second or third vehicle scheduled even when its
live board was available.

RAPTOR first builds candidate itineraries. The acquisition phase requests missing
boarding or arrival evidence for their transit legs, including walking and
stay-aboard connections. These requests follow actual boarding occurrences and
do not inherit discovery's 24-stop or eight boarding-seed limits. Patch
construction prioritizes the selected vehicles; matching still checks the full
timetable for ambiguity.

Occurrence windows include the permitted two-hour delay range and end at the
route search horizon. Shared board coverage merges compatible intervals and
fetches missing coverage. Four stop requests run concurrently. The app allows
up to eight seconds of live acquisition, replacing the two-second cutoff that
cancelled available connecting boards before their responses arrived. Routing
work is measured separately. The allowance is a deadline, not a mandatory wait.

New evidence triggers another RAPTOR scan before publication. Connecting-trip
cancellations, delays and restrictions therefore affect route feasibility and
ranking. Replacement itineraries can acquire additional missing vehicles for up
to four completion waves. Each boarding occurrence is attempted once during
completion. Remaining time permits broad discovery. Sparse raw observations
survive until later stop reports can resolve a usable trip timeline. Unavailable,
ambiguous, contradictory or expired reports retain honest scheduled or partial
coverage.

The app pins MobiliteitKit revision
`b0d3d91f40a057f1408d7a8b614139d29e7b1d75`.

## Verification

On 4 October 2026, all 181 package tests in 22 suites passed with
`ROUTING_VERIFY_KERNEL=1 swift test --disable-automatic-resolution --no-parallel`.
Regressions cover stalled discovery branches ahead of a live connecting trip for
both departure and arrive-by searches, live predictions on all three vehicles,
cancellation and missed-connection removal, cache reuse, explicit refresh,
timestamp-free merging, full-timetable ambiguity with targeted matching, and
session deadlines extending beyond standalone provider timeouts.

The simulator build and 11 journey-planning integration and continuation tests
pass. The full app suite currently reports 34 fixture issues; an isolated project
with the previous `f198548` router pin reproduces all 34 issue locations and
counts. These failures are outside this router change.

## Live comparison

Four opt-in simulator calculations on 4 October 2026 covered both live-now and
reverse searches. All 40 uniquely matched displayed boarding occurrences with
an available board prediction used that prediction on the first calculation.
A subsequent shared-cache comparison also applied all 40. The remaining displayed
scheduled occurrences matched board entries with no realtime departure; they
were not promoted to live. This is a sampled check, not a guarantee of future
upstream data availability.

Rendered calculation times were 12.30, 11.39, 11.08 and 10.22 seconds. Prior
runs with a two-second acquisition cap rendered in about four seconds but missed
available connecting reports. The longer acquisition allowance restores coverage
and adds a latency cost; this check does not meet the existing five-second
performance gate. The gate was disabled explicitly for this network-dependent
coverage diagnostic.

Reproduce after a Release simulator build and installing current GTFS and walking
graphs:

```sh
python3 Scripts/benchmark_routes.py \
  --app /path/to/Release-iphonesimulator/Verkeier.app \
  --output /tmp/verkeier-live-coverage \
  --scenarios live-now live-reverse --warm 1 --cold 0 --p95-limit-ms 0
```
