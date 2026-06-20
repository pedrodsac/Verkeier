# LuxTransit App Audit and Feature Checklist

Date: 2026-06-20

## Scope

This audit covers the current SwiftUI iOS app as exercised on Simulator and reviewed from the main feature, service, and model code. It focuses on feature opportunities, visible UI issues, likely bugs, and performance risks.

## Evidence

- Built and launched `LuxTransit` on iPhone 17 Pro, iOS 27.0 simulator.
- Also launched earlier on iPhone 17, iOS 26.5 simulator.
- Granted simulator location and set location to Luxembourg City (`49.6116, 6.1319`).
- Captured screenshots in `docs/audit-screenshots/`.
- Ran the test suite after clearing manual simulator handoff state: 81 passed, 0 failed.
- Note: XcodeBuildMCP semantic UI snapshots and gestures failed in this environment because `/Applications/Xcode.app/Contents/Developer/Library/PrivateFrameworks/SimulatorKit.framework` is missing. Screenshot capture and build/test were usable.

## Screenshots

| Screen | Path | Notes |
| --- | --- | --- |
| Home map and medium sheet | `docs/audit-screenshots/iphone17pro-home-empty.jpg` | Shows live map, location control, disruptions row, nearby stops, and search/settings controls. |
| External deep link prompt | `docs/audit-screenshots/iphone17pro-route-deeplink-hamilius.jpg` | `simctl openurl` triggers the system "Open in LuxTransit?" prompt. |
| Handoff/search state | `docs/audit-screenshots/iphone17pro-handoff-route-hamilius.jpg` | Shows search results for "Hamilius" behind the external URL prompt. |
| Initial iPhone 17 run | `docs/audit-screenshots/iphone17-nearby-initial.jpg` | Earlier launch capture from iOS 26.5 simulator. |

## Feature Opportunities

- [ ] **P0 - Production data readiness screen.** Add a first-run or settings-visible data status view that clearly explains ATP, GTFS, AVL, and route data availability, last update time, and whether the app is using live, cached, or empty/mock data.
- [ ] **P0 - Local GTFS bootstrap flow.** Ship a compact bundled GTFS seed or make the launch-time GTFS download progress explicit. Without a seed, search and routing quality depends on a successful background update.
- [ ] **P0 - Door-to-door route planner.** Expand routing beyond "current location to selected stop" with origin and destination pickers, recent places, favorites, and map-selected points.
- [ ] **P0 - Route filters.** Add fastest, fewest transfers, least walking, accessible, tram/train/bus preference, and "avoid tight transfers" controls.
- [ ] **P0 - Transfer reliability.** Surface transfer windows, missed-connection risk, and automatic alternatives when a live delay makes the selected route weak.
- [ ] **P1 - Stop detail platform grouping.** Group departures by physical platform/quay with a clearer platform selector, especially for grouped ATP stops.
- [ ] **P1 - Line detail pages.** Let users tap a route/line chip to see direction, stop sequence, full timetable, disruption impact, and map polyline.
- [ ] **P1 - Disruption impact mapping.** Link AVL alerts to affected stops/routes on the map and in stop detail, not only in a global alert list.
- [ ] **P1 - Favorite commute presets.** Let users save "Home to Work", "Work to Home", and favorite line/stop combinations instead of only favorite stops.
- [ ] **P1 - Recent searches and places.** Add recents for stops, routes, and destinations to reduce repeated typing.
- [ ] **P1 - Departure reminders.** Add local notifications for "leave in X minutes", "departure delayed", and "departure cancelled" when tracking a trip.
- [ ] **P1 - Live Activity controls.** Add explicit stop/end tracking controls and a visible explanation of stale Live Activity updates.
- [ ] **P1 - Widget configuration.** Let users configure which favorite stop or commute appears in each widget, with honest refresh-state text.
- [ ] **P1 - Accessibility travel filters.** Include wheelchair boarding, low walking distance, step-free transfer hints, and larger departure-board mode.
- [ ] **P1 - Multilingual UI.** Add English, French, German, Luxembourgish, and Portuguese localization for Luxembourg usage.
- [ ] **P2 - Nearby walking ETA.** Add distance and walking time to nearby stop rows and map callouts.
- [ ] **P2 - Map clustering and density controls.** Cluster nearby stops, distinguish favorite markers strongly, and let users filter by bus/tram/train.
- [ ] **P2 - Offline schedule browser.** Allow browsing GTFS schedules and stop timetables when live ATP data is missing.
- [ ] **P2 - Shareable route summaries.** Export selected route steps as text or a share sheet payload.
- [ ] **P2 - Diagnostics export.** Add a support bundle with app version, data-source status, last GTFS update result, and relevant non-secret logs.

## Bugs, UI Issues, and Slowdown Risks

- [ ] **P0 - Favorite markers are not visually distinguished in the active MapKit implementation.** `TransitMapScreen.swift` passes `isFavourite` into `markerColor(...)`, but `markerColor` ignores it. Favorite stops may not stand out on the map even though the older unused SwiftUI marker code has a yellow favorite stroke.
- [ ] **P0 - Shared UserDefaults state can contaminate tests and handoff behavior.** `TransitIntentHandoff` uses `UserDefaults.standard`; manually injected simulator state caused `handoffRoundTripsAndConsumesOnce()` to fail until the default was cleared. Prefer a small injectable store or a test-specific suite.
- [ ] **P1 - SwiftData/CoreData app-group store path logs a startup recovery error.** Runtime logs showed CoreData failing to create `Library/Application Support/default.store` under the app group, then recovering. Create the app-group Application Support directory explicitly before SwiftData opens the store or confirm this is simulator-only.
- [ ] **P1 - External URL confirmation can obscure target state.** Deep-linking with `luxtransit://route?destination=Hamilius` opened the search state behind an iOS "Open in LuxTransit?" prompt. Validate widget/App Intent entry points and consider Universal Links or clearer app-internal handling where possible.
- [ ] **P1 - "Search Maps" copy feels off-brand.** The main search button says "Search Maps", but this app searches stops and routes. Use "Search stops" or "Search stops and routes".
- [ ] **P1 - Settings affordance is ambiguous.** The medium sheet uses an ellipsis button for settings and information. A gear, menu label, or visible context menu would be clearer.
- [ ] **P1 - Nearby list lacks distance and route context.** The home sheet shows stop name/locality/mode but not distance, walking ETA, served lines, or live departure preview unless saved as a favorite.
- [ ] **P1 - Route "Show 3 more" is always visible when route options exist.** `RouteOptionsSection` shows the button even when all available options are already visible, then reports "No later public transport options were found." Disable or hide the button when no more options remain.
- [ ] **P1 - Route badges use very small text.** `RouteOptionBadge` uses `.caption2.weight(.bold)`, which is fragile for Dynamic Type and glanceability.
- [ ] **P1 - Some animations ignore Reduce Motion.** Sheet context changes check `accessibilityReduceMotion`, but `SearchView` and card expansion use `.snappy(...)` directly.
- [ ] **P1 - Map annotation churn risk.** Map region changes schedule GTFS stop reloads every 120 ms and sync up to 180 annotations. The annotation diff is reasonable, but dense panning can still trigger repeated spatial queries and annotation reconfiguration.
- [ ] **P1 - Broad view model invalidation risk.** `TransitMapViewModel` is a single `@Observable @MainActor` type that feeds map, sheet, search, departures, routes, alerts, and favorites. Small changes can rebuild the full `TransitSheetPresentationModel`.
- [ ] **P1 - Favorite departures load sequentially.** `loadFavouriteDepartures` loops through up to six favorites one by one. Use a task group with bounded concurrency to cut refresh time.
- [ ] **P1 - Large files are slowing maintenance.** The largest files are `PublicTransportRouteService.swift` (1332 lines), `TransitMapScreen.swift` (1185), `RouteView.swift` (803), `TransitMapViewModel.swift` (616), and `StopDetailView.swift` (594). Split by route search, route overlay, map container, sheet state, and row components.
- [ ] **P2 - Search result accessory icon is unclear.** `arrow.up.left.and.arrow.down.right` reads like expand/resize, not "select stop" or "open stop".
- [ ] **P2 - Departure row alignment can look unstable.** `DepartureListRow` gives the destination stack `frame(maxWidth: .infinity)` without leading alignment, while also using a spacer and trailing timing column. Long destinations may compress awkwardly.
- [ ] **P2 - Alert list is global-only.** Alerts are useful on home, but stop detail and route planning do not visibly show which listed disruptions affect the selected journey.
- [ ] **P2 - Settings diagnostics are mostly static.** API diagnostics say "Mocked" or "Configured", but do not show last successful ATP/AVL request, response status, stale age, or source-specific errors.
- [ ] **P2 - App identity is weak on the first screen.** The first viewport looks close to Apple Maps and does not visibly say LuxTransit. That is good for familiarity, but add subtle app identity in settings/home empty states to avoid feeling like an Apple Maps clone.
- [ ] **P2 - Debug/test data entry paths are implicit.** The app can be hard to QA without an ATP key or downloaded GTFS. Add a debug-only sample data mode or fixture toggle so empty, stale, error, live, and disruption states can be tested deliberately.

## Verification Notes

- Build/run: `build_run_sim` succeeded on iPhone 17 Pro, iOS 27.0.
- Tests: `test_sim` passed with 81 tests after clearing manually injected `TransitIntentHandoff` state.
- Initial contaminated test run: 80 passed, 1 failed because the simulator contained a manually inserted handoff default from this audit. It was cleared and rerun successfully.
- Runtime logs: one iOS 27 launch logged a duplicate UIKit/AutoFill class warning from the simulator runtime. Treat as simulator noise unless reproduced on device.

## Suggested First Pass

- [ ] Fix favorite marker visual state.
- [ ] Isolate App Intent handoff storage for tests.
- [ ] Rename "Search Maps" and clarify the settings/menu affordance.
- [ ] Add distance/walking ETA to nearby rows.
- [ ] Hide "Show 3 more" when no route options remain.
- [ ] Split `TransitMapScreen` and route service files before adding larger route-planning features.
