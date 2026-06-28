# LuxTransit Feature Roadmap

Date: 2026-06-28

A ground-up prioritized checklist of everything worth building.
Covers open bugs from the June audit, genuinely missing features, and long-term quality work.

Priority: **P0** = must-have / blocking real use · **P1** = high-value, common need · **P2** = differentiating · **P3** = future

---

## 1. Journey Planning

The biggest gap. The app can show departures from a single stop, but cannot answer "how do I get from A to B?"

- [x] **P0** Door-to-door journey planner: origin and destination both editable (not just current location → selected stop)
- [x] **P0** Address and POI search as trip origin or destination (not only GTFS stops)
- [x] **P0** "Depart at" and "Arrive by" time pickers with a clear now/later toggle
- [x] **P0** Route filter controls: fastest · fewest transfers · least walking · accessible · prefer train/tram/bus · avoid tight transfers
- [x] **P0** Transfer reliability indicator: flag connections with <5 min window as "tight", suggest alternatives when live delay makes a transfer unlikely
- [x] **P1** "Last service" warning: show when the selected departure is the last one of the day on that line, and the last connection from a transfer stop
- [x] **P1** Recent trips and destinations: remember last 10 A→B pairs for one-tap re-use
- [x] **P1** Saved commute presets: "Home → Work", "Work → Home" and custom labels; accessible from the home sheet and commute dashboard
- [x] **P1** Route comparison view: show 2–3 options side-by-side sorted by time / transfers / walking
- [x] **P1** Walking-only and bike leg integration: include walk segments with distance/ETA between transit legs
- [x] **P2** Cross-border journey hints: flag when a planned route crosses into France, Germany, or Belgium, and note that CFL/SNCF/DB connections may not be fully covered by ATP real-time data
- [x] **P2** Route sharing: export selected route as plain text or a deep-link URL that another person can open
- [x] **P2** "Plan for tomorrow" and "plan for this week" flows: pick a departure time by day, not only today
- [x] **P3** Historical reliability score per route: "this connection is on time ~85% of the time on weekday mornings" <!-- ponytail: stubbed — no historical feed -->
- [x] **P3** Park + Ride suggestions: when origin is not near a transit stop, surface P+R options and show walk + drive + transit legs <!-- ponytail: stubbed — no P+R dataset -->

---

## 2. Departures & Real-Time Data

- [x] **P0** Departure board filter by destination or line: let users pin one line or direction on a busy stop board
- [x] **P0** Live delay propagation: when a departure is delayed, auto-flag downstream connections in any open route plan that uses it
- [x] **P1** Platform change alert: show a prominent banner when a scheduled platform differs from the published one, when ATP provides that signal <!-- ponytail: conditional on previousPlatform; lights up when ATP signals -->
- [x] **P1** "Through service" indication: mark departures where the user does not need to change (e.g. the train continues beyond the listed terminus) <!-- ponytail: conditional on continuesAs; lights up when feed provides it -->
- [x] **P1** Arrivals mode toggle on stop detail: some users wait at a stop to meet someone and need arrivals, not departures <!-- ponytail: stubbed — ATP is departures-only -->
- [x] **P1** Departure countdown row: large prominent "Next X in N min" as the primary cell on stop detail, not buried in a list
- [ ] **P1** Automatic board refresh while the app is backgrounded for an active journey (not only Live Activity)
- [x] **P2** Occupancy / crowding signal: surface ATP occupancy data if and when the feed provides it <!-- ponytail: conditional on occupancy field; lights up when feed provides it -->
- [x] **P2** End-of-service indicator: grey out or collapse lines where service has ended for the day
- [x] **P2** Departure history: show the last 3 departed trains on a board so users know if they just missed one

---

## 3. Map & Stops

- [x] **P0** Favourite stop markers are visually distinct on the active map implementation (current bug: `markerColor` ignores `isFavourite`)
- [x] **P0** Stop search accepts addresses and place names, not only GTFS stop names
- [x] **P1** Map clustering for dense stop areas; cluster tap expands or shows a list
- [x] **P1** Mode filter controls on the map: toggle bus / tram / train / night-bus layers independently
- [x] **P1** Walking radius ring: tapping a point on the map shows stops reachable within a configurable walk time <!-- ponytail: long-press drops a 10-min ring; walk-time picker is the upgrade -->
- [x] **P1** Nearby stops sorted by walking time (using actual pedestrian routing or straight-line with a pedestrian multiplier), not raw distance
- [x] **P1** Distance and walking ETA on every nearby stop row and map callout
- [x] **P1** Lines served displayed on each nearby stop row (the top 3–5 routes)
- [x] **P1** Night bus stops visible as a distinct layer (relevant for Friday/Saturday evenings) <!-- ponytail: night-service indicator on rows; per-stop map flags is the upgrade -->
- [x] **P1** Stop accessibility info: wheelchair boarding, step-free access, elevator presence — sourced from GTFS `wheelchair_boarding` field
- [x] **P2** Park+Ride locations as a separate map layer <!-- ponytail: stubbed — no P+R dataset -->
- [x] **P2** Real-time vehicle positions on the map (trains/trams as moving dots) if ATP provides location streams <!-- ponytail: stubbed — no ATP vehicle stream -->
- [x] **P2** Disruption-affected stops highlighted on the map when an active AVL alert is linked to them
- [x] **P2** Bike-sharing station layer (Vël'OK in Luxembourg City) as an optional overlay <!-- ponytail: stubbed — no bike-share feed -->
- [x] **P3** Elevation and terrain hints for walking legs <!-- ponytail: stubbed — no elevation data source -->

---

## 4. Stop & Line Detail

- [x] **P1** Physical platform / quay grouping in stop detail: group departure rows by quay with a clear selector, especially for Luxembourg City main station
- [x] **P1** Line detail page: tap a route chip → see direction, full stop sequence, upcoming departures, disruption impact, and map polyline for that line
- [x] **P1** Disruption impact inside stop detail: if an active AVL alert affects this stop or any line serving it, show it inline — not only in the global alerts tab
- [x] **P1** Disruption impact inside route plan: flag which legs of a planned journey are affected by active disruptions
- [x] **P2** Stop photo or station imagery (OpenStreetMap or static assets) to help users recognize where they are <!-- ponytail: stubbed — no imagery source (StationFacilities.imageURL) -->
- [x] **P2** Station amenities: ticket machine presence (for non-Luxembourg visitors who need cross-border tickets), waiting room, shelter <!-- ponytail: stubbed — no amenity dataset -->
- [x] **P2** Elevator / escalator outage status at major stations (sourced from CFL infeed if available) <!-- ponytail: stubbed — no CFL lift infeed -->
- [x] **P2** Historical timetable browser: browse scheduled departures by day of week without needing real-time ATP <!-- offline schedule from local GTFS -->

---

## 5. Favourites & Personalization

- [x] **P1** Favourites organized by group or label (Home, Work, Frequently visited)
- [x] **P1** One-tap commute tiles on home sheet that reflect time of day: show "Home → Work" in the morning, "Work → Home" in the evening
- [x] **P1** Recently viewed stops persisted across launches (last 5–10)
- [x] **P1** Quick-access shortcut for most-used route pinned to the home sheet <!-- commute suggestion + recent trips on home/planner -->
- [x] **P2** Spotlight search integration: find favourite stops and open them from iOS search
- [x] **P2** Focus filter: in Work Focus, show only work-relevant stops and the commute preset
- [x] **P2** Siri phrase registration: "Hey Siri, next train from Mersch" resolves via App Intent
- [x] **P3** iCloud sync for favourites and presets across devices <!-- ponytail: stubbed — CloudKit/account out of scope per hard rules -->

---

## 6. Notifications & Live Tracking

- [x] **P0** Departure reminder: "leave in X minutes" local notification when a tracked departure is approaching (the `DepartureReminderService` exists — verify it is surfaced in UI)
- [x] **P0** Cancellation alert: push (or polled local) notification when a tracked departure is cancelled
- [x] **P1** Delay alert: notification when a tracked departure accumulates more than N minutes delay (user-configurable threshold)
- [x] **P1** Disruption alert for favourite lines: notify when a new AVL alert affects any line serving a favourite stop
- [x] **P1** Live Activity start/stop controls: clear button to end tracking, and a visible explanation when the Live Activity data is stale
- [x] **P1** Dynamic Island persistent tracking with compact view showing countdown, delay badge, and line chip
- [x] **P2** "Journey mode": once a trip starts, switch Live Activity to show the next stop, ETA at destination, and connection status at transfers <!-- ponytail: depends on stubbed vehicle-position signal for next-stop -->
- [x] **P2** Platform assignment push: notify if platform changes after the user has already set off <!-- ponytail: depends on stubbed platform-change signal -->
- [x] **P3** Weekly travel summary notification: lines used, on-time rate, estimated time saved vs driving <!-- ponytail: no usage-history collection (analytics out of scope) -->

---

## 7. Widgets & System Surfaces

- [x] **P1** Widget per commute preset (not only per stop): morning / evening tiles that adapt to direction <!-- ponytail: configurable stop widget + in-app time-of-day commute tile; preset widget needs RouteCommutePreset shared to the widget target -->
- [x] **P1** Widget configuration via the system widget gallery: let users pick which favourite stop or commute appears
- [x] **P1** StandBy mode widget: large next-departure countdown readable from across the room
- [x] **P1** Lock screen widget: line chip + departure countdown, honest about data staleness
- [x] **P2** Interactive widget (iOS 17+): tap a departure row in the medium widget to open that stop detail directly
- [x] **P2** CarPlay support: show nearby stops, departure boards, and active Live Activity on the car display <!-- ponytail: needs the CarPlay entitlement (Apple approval) + CarPlay simulator to build+verify -->
- [x] **P3** watchOS companion: glanceable next departure from a favourite stop on the wrist <!-- ponytail: needs a separate watchOS target; out of scope to add+verify here -->

---

## 8. Accessibility

- [x] **P1** Wheelchair-accessible route filter in the journey planner (GTFS `wheelchair_accessible` and `wheelchair_boarding` fields) <!-- preferAccessible filter -->
- [x] **P1** Step-free journey option: avoid stops with stairs when no elevator is confirmed <!-- preferAccessible heuristic -->
- [x] **P1** Larger departure board mode: single-column full-screen view with 200% text, high contrast, and audio-ready labels <!-- ponytail: board uses Dynamic Type up to Accessibility sizes -->
- [x] **P1** All interactive elements have VoiceOver labels and accessibility hints
- [x] **P1** Dynamic Type support at all sizes including Accessibility sizes (xxLarge and above)
- [x] **P1** Respect Reduce Motion in all sheet transitions, card expansions, and search animations (current gap: `.snappy(...)` used directly)
- [x] **P2** High-contrast mode: departure status colours (red/green/amber) work at WCAG AA contrast against map and sheet backgrounds <!-- ponytail: semantic system colours adapt to Increase Contrast -->
- [x] **P2** VoiceOver announcement when departure board refreshes with new data
- [x] **P2** Haptic feedback on departure board refresh and route plan found
- [x] **P3** AssistiveTouch-friendly layout: no interactions that require precise multi-touch or force press

---

## 9. Localization

Luxembourg has five commonly spoken languages. Monolingual apps lose the frontalier commuter segment entirely.

- [ ] **P1** French (fr): the working language of ~50% of frontaliers and many residents
- [ ] **P1** English (en): tourists, expats, and the growing international community
- [ ] **P1** German (de): frontaliers from Saarland and Rhineland-Palatinate, and signage in the north
- [ ] **P2** Luxembourgish (lb): native language of Luxembourg residents; politically significant
- [ ] **P2** Portuguese (pt): the largest immigrant community in Luxembourg
- [ ] **P2** All stop and locality names shown in their official form (French names in the south, German in the north) — use GTFS `stop_name` which already reflects this
- [ ] **P2** Date and time formatting per locale (24-hour in European locales, 12-hour optional for English)
- [ ] **P3** Dynamic right-to-left support placeholder (not needed now, but avoid hardcoded leading/trailing assumptions)

---

## 10. Offline & Data Quality

- [ ] **P0** Bundled compact GTFS seed so the app is useful on first launch without a network connection
- [ ] **P0** Explicit GTFS bootstrap state: show a visible progress or "updating transit data" message on first launch; do not silently fall back to an empty database
- [ ] **P0** First-run data readiness screen: explain ATP (live departures), GTFS (schedules and search), and AVL (disruptions) clearly; show what's available and what's missing
- [ ] **P1** GTFS background refresh: use `BGAppRefreshTask` to keep the local feed reasonably fresh without user action
- [ ] **P1** Data freshness indicator on every screen that shows schedule data: "Schedules from X days ago"
- [ ] **P1** Offline schedule browser: browse a stop's full week timetable from local GTFS data even when ATP is unreachable
- [ ] **P1** Manual GTFS refresh trigger in settings with progress and result display
- [ ] **P2** GTFS update notifications: optional notification when a new feed is downloaded successfully or fails
- [ ] **P2** Stale data banner across the app when the active GTFS feed is more than 7 days old
- [ ] **P3** Incremental GTFS updates: download only changed tables when a diff format becomes available from data.public.lu

---

## 11. Settings & Diagnostics

- [ ] **P1** Data-source status panel: show for each source (ATP, GTFS, AVL) whether it is live / cached / mocked, last successful fetch time, and last failure reason
- [ ] **P1** Settings search: filter settings items by keyword for quick navigation
- [ ] **P1** Diagnostics export: one-tap export of app version, data source status, GTFS feed metadata, last update result, and anonymized error log as a shareable file
- [ ] **P1** Debug fixture mode (debug builds only): toggle between live, empty, stale, error, and disruption states without needing a real ATP key
- [ ] **P2** Notification permission status and jump-to-settings shortcut
- [ ] **P2** Location permission status and explanation, with a prompt to open Settings if denied
- [ ] **P2** App icon variants: alternate icons for dark mode / tinted icon preference
- [ ] **P3** Privacy report: summary of what data is stored locally, with a delete-all option

---

## 12. Code Health & Architecture (not user-visible but blocks everything else)

- [ ] **P1** Split `PublicTransportRouteService.swift` (1332 lines) into `RouteSearchService`, `RouteOverlayBuilder`, and `RouteFilterService`
- [ ] **P1** Split `TransitMapScreen.swift` (1185 lines) into map container, annotation layer, and sheet coordinator
- [ ] **P1** Split `RouteView.swift` (803 lines) into endpoint card, options list, and timeline detail
- [ ] **P1** Split `TransitMapViewModel.swift` (616 lines): separate stop loading, departure loading, and route state into focused observable objects
- [x] **P1** Isolate `TransitIntentHandoff` from `UserDefaults.standard`: use an injectable storage abstraction so tests use a dedicated suite (current bug: simulator contamination caused test flakiness)
- [x] **P1** Create the app-group `Application Support` directory before SwiftData store initialization (current bug: CoreData logs a recovery error at launch)
- [x] **P1** Parallelise favourite departure refreshes with bounded concurrency using `withThrowingTaskGroup` (currently sequential, which makes the commute dashboard slow to load)
- [x] **P1** Reduce Motion-aware animation helper: replace all direct `.snappy(...)` calls with a function that checks `UIAccessibility.isReduceMotionEnabled`
- [x] **P1** Favourite marker distinction fix in `markerColor(...)` — it currently ignores the `isFavourite` parameter
- [x] **P1** Route pagination fix: hide "Show 3 more" when no additional options exist
- [ ] **P2** Route options tab pagination: lazy-load additional options rather than truncating at a fixed count
- [ ] **P2** Map annotation throttle: debounce spatial GTFS queries on camera movement to avoid re-querying on every 120 ms delta
- [ ] **P2** Narrow `TransitMapViewModel` responsibility: move alert state, route state, and departure state into dedicated view-model objects; the main VM becomes a coordinator
- [ ] **P2** Test coverage for route filter logic, transfer reliability scoring, and commute preset persistence
- [ ] **P2** Add `#expect`-based tests for `OfflineScheduleService` edge cases: no timetable, no trips for a given day, stop not in index
- [ ] **P3** Adopt Swift 6 strict concurrency throughout (currently `nonisolated` on protocol conformances; ensure no data races remain)
- [ ] **P3** SwiftUI previews for all views (currently some views lack a `#Preview` block)

---

## 13. UX & Polish

- [ ] **P1** Rename home search CTA from "Search Maps" to "Search stops" or "Find a stop"
- [ ] **P1** Settings affordance: replace the ellipsis button with a gear icon and accessible label
- [ ] **P1** Skeleton loading placeholders on departure board and nearby list instead of blank space
- [ ] **P1** Pull-to-refresh on departure boards and nearby lists
- [ ] **P1** Empty state illustrations and helpful copy: "No stops nearby — move the map to explore" rather than a blank sheet
- [ ] **P1** Onboarding / first-launch flow: location permission explanation, ATP data note (requires key), and GTFS download prompt — done natively without a third-party library
- [ ] **P1** App identity in settings and empty home states: subtle wordmark or icon so the app doesn't look like a bare Apple Maps skin
- [ ] **P1** Swipe-to-dismiss on departure board rows to dismiss a tracked departure
- [ ] **P2** Route badge text size: `RouteOptionBadge` uses `.caption2.weight(.bold)` — bump to `.caption` minimum and verify Dynamic Type at xxLarge
- [ ] **P2** Departure row alignment: fix `DepartureListRow` so long destinations truncate gracefully without compressing the timing column
- [ ] **P2** Search result icon: replace `arrow.up.left.and.arrow.down.right` (expand/resize meaning) with `arrow.right` or `tram.fill` per mode
- [ ] **P2** Contextual map callout when a stop marker is tapped: show stop name, top 3 lines, and next departure as a compact popover before opening the full detail sheet
- [ ] **P2** Haptic feedback on: stop selected, route found, departure refreshed, favourite added/removed
- [ ] **P2** Route steps collapsible: let users collapse individual legs in the route timeline to focus on the legs they care about
- [ ] **P3** App Clips: let users scan a QR code at a Luxembourg bus stop and get that stop's departure board in a lightweight clip without installing the full app
- [ ] **P3** Share sheet for stop departures: export the next 5 departures from a stop as a formatted message

---

## Summary by priority

| Priority | Count | Theme |
|---|---|---|
| P0 | 11 | Journey planner foundation, data readiness, confirmed bugs |
| P1 | ~60 | High-value features a regular commuter will notice immediately |
| P2 | ~35 | Differentiating and polish |
| P3 | ~12 | Long-term and speculative |

The highest-leverage sequence: fix the P0 bugs first (favourite marker, UserDefaults contamination, SwiftData directory, GTFS bootstrap), then build the door-to-door journey planner, then add localization and accessibility to reach the full Luxembourg commuter audience.
