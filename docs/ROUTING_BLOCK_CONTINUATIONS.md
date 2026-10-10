# Buses continuing under another line number

MobiliteitKit revision `b2e7b6709eeb2f3b4ffdfce203801239614e129a` recognizes consecutive trips with the same GTFS `block_id` as stay-aboard connections. Previously, only explicit type-4 entries in `transfers.txt` could create these connections, although the Luxembourg feed also describes them through vehicle blocks.

On 10 October 2026, the installed generation-5 timetable links trip `24427999` (line 7) to `24424738` (line 25), block `574`. The replay boards at Kirchberg, Gare routière Luxexpo at **20:33:20**, stays aboard at Poutty Stein between **20:34:40 and 20:35:10**, and arrives at Kirchberg, prov. Konrad Adenauer at **20:39:10**. This connection has zero transfers; it does not need a separate 211 ride to reach the 25.

The engine checks active trips on the same service day, scheduled vehicle order, matching boundary stops and transport types. Missing, overlapping or ambiguous blocks cannot establish a continuation. It cannot skip an intervening trip. Explicit transfer restrictions override block inference, while generic stop boarding buffers do not apply to passengers remaining aboard. Live cancellation and timing checks still apply. Frequency templates and cross-service-day block inference are excluded.

The app already maps verified continuations into its timeline, sharing, accessibility, transfer counts and itinerary validation. No route-number-specific exception or production data is embedded in the app.

The bus detail page also follows verified onward runs, using MobiliteitKit revision `e881780`. It lists each onward line under a “Stay aboard at…” / “Continues as…” heading and includes its geometry on the map. Stop sequences, cancellations and live reports remain scoped to their original run; an unavailable onward report does not stale fresh incoming-run data. When opened from a route timeline, the selected ride and its verified onward journey legs are highlighted through their selected alighting occurrences in both the stop list and map. Further onward runs outside the itinerary remain context. A simulator-only `--trip-continuation-preview` launch mode provides an explicitly labelled 7 → 25 fixture, with `--trip-detail-accessibility` for large-text inspection. Both the normal and accessibility-size layouts were inspected on iPhone 17.

Verification:

- Full routing package suite: 242 tests in 36 suites passed (installed-feed replays are opt-in).
- Full app suite: 192 tests in 33 suites passed on iPhone 17, Release, coverage disabled.
- Installed-feed replay: the 20:33 line 7 → 25 connection above passed using a local timetable, without network requests.
- Fixture coverage includes departure and arrival searches, a 30-second continuation despite a generic 450-second transfer buffer, explicit restrictions, invalid blocks and app mapping for both explicit links and vehicle blocks.

The block and linked-trip semantics are defined in the [GTFS Schedule reference](https://gtfs.org/documentation/schedule/reference/).
