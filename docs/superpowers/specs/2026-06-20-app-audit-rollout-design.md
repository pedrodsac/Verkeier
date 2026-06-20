# LuxTransit App Audit Rollout Design

Date: 2026-06-20

## Objective

Implement every feature and fix listed in `docs/APP_AUDIT_FEATURE_CHECKLIST_2026-06-20.md` through a phased rollout that keeps the app buildable and verifiable at each milestone.

## Why A Phased Rollout

The audit items span multiple independent subsystems:

- map annotations and nearby stop presentation
- GTFS bootstrap, diagnostics, and offline readiness
- routing architecture and door-to-door planning
- stop, line, alert, and disruption surfaces
- widgets, App Intents, Live Activities, and notifications
- accessibility, localization, diagnostics export, and QA tooling

Landing all of that in one branch would make regressions difficult to isolate and verification weak. The implementation will therefore proceed in milestones that each leave the app in a shippable state while preserving the full audit scope.

## Rollout Overview

### Milestone 1: Foundation Stabilization

Purpose: remove concrete bugs and weak state boundaries that block later work.

Includes:

- fix favourite marker visual distinction in the active map implementation
- isolate App Intent handoff persistence from `UserDefaults.standard`
- create the app-group `Application Support` directory before SwiftData store initialization
- rename misleading home search copy and clarify the settings affordance
- add nearby-stop distance and walking ETA presentation
- hide or disable route pagination controls when no more options exist
- respect Reduce Motion in search and expansion animations
- parallelize favourite departure refreshes with bounded concurrency
- improve data-source and GTFS diagnostics in settings

Deliverable: a more trustworthy baseline for map, settings, persistence, tests, and nearby/routing presentation.

### Milestone 2: Data Readiness And Offline Awareness

Purpose: make the app’s data state explicit and usable even when live feeds are unavailable.

Includes:

- first-run or settings-visible data readiness screen
- explicit GTFS bootstrap state, including bundled seed or visible launch-time progress
- live versus cached versus empty/mock source status
- offline schedule browser for local GTFS data
- richer source-specific settings diagnostics, stale age, and last-success metadata
- diagnostics export support bundle
- debug-only fixture mode for empty, stale, error, live, and disruption states

Deliverable: a transparent data lifecycle with clear user messaging and QA coverage.

### Milestone 3: Door-To-Door Routing

Purpose: expand routing from “current location to selected stop” into a real trip planning surface.

Includes:

- origin and destination pickers
- recent places, favourite commute endpoints, and map-selected points
- route filters for fastest, fewest transfers, least walking, accessible, tram/train/bus preference, and avoid-tight-transfers
- transfer reliability scoring and alternative suggestions when live delays weaken a route
- route result modeling that can carry filter metadata, walking burden, and transfer risk

Deliverable: a route planner that no longer depends on selecting a stop first.

### Milestone 4: Stop, Line, And Disruption Depth

Purpose: connect stops, lines, and disruptions into a coherent navigation model.

Includes:

- grouped stop detail platform and quay presentation
- tappable line detail pages with direction, stop sequence, timetable, disruption impact, and map polyline
- disruption impact mapping into stop detail, line detail, and planned journeys
- nearby rows and callouts showing route context and walking information
- map clustering and density filters by mode
- stronger app identity in home/settings empty states

Deliverable: richer exploration and clearer system status directly from map, stop, and route surfaces.

### Milestone 5: Personalization And System Surfaces

Purpose: make the app useful for repeated daily travel patterns.

Includes:

- favourite commute presets like “Home to Work”
- recent searches, routes, and destinations
- configurable widgets for chosen favourite stop or commute
- departure reminders and tracking notifications
- explicit Live Activity start/stop controls and stale-update explanations
- shareable route summaries
- better widget honesty around refresh behavior

Deliverable: repeat-trip workflows across app, widgets, and Live Activities.

### Milestone 6: Accessibility, Localization, And Structural Cleanup

Purpose: finish cross-cutting quality requirements and reduce maintenance risk.

Includes:

- multilingual UI for English, French, German, Luxembourgish, and Portuguese
- accessibility travel filters and larger departure-board mode
- remaining Reduce Motion, Dynamic Type, and clarity fixes
- decomposition of oversized files, especially routing, map screen, route view, and stop detail
- narrower presentation/view-model boundaries to reduce broad invalidation risk

Deliverable: the full audit scope completed with sustainable code boundaries.

## Milestone 1 Design

### 1. Handoff And Shared State Isolation

`TransitIntentHandoff` will no longer hardcode `UserDefaults.standard`. Introduce a small storage abstraction that supports:

- default app behavior backed by app-group or standard defaults as appropriate
- test-only isolated suites
- one-shot consume semantics

Tests will create dedicated suites and clear only that scoped storage. This removes simulator contamination and makes deep-link/App Intent tests deterministic.

### 2. SwiftData App-Group Store Preparation

Before the shared or grouped persistence store is opened, the app will ensure the relevant `Application Support` directory exists. The directory bootstrap must be explicit and idempotent. If grouped storage is not yet fully adopted in one place, the preparation logic must still cover the active store path used by the app at launch.

### 3. Nearby And Home UI Corrections

The home search CTA will use transit-specific wording. The settings affordance will use a clearer icon and accessible label. Nearby rows will gain:

- distance from current location
- approximate walking ETA

Those values will also be available in the favourite-empty-state nearby suggestions so the home sheet conveys useful ranking context.

### 4. Map Favourite Marker Fix

Favourite state must affect the active map annotation styling, not only older or unused implementations. The selected visual treatment should remain readable against the map and distinct from non-favourite stops without obscuring mode color.

### 5. Route Options Pagination Fix

The route options section will only show “Show 3 more” when hidden results remain. When all options are already visible, the control disappears rather than leading the user into a no-op state.

### 6. Reduce Motion Compliance

Animations currently using `.snappy(...)` directly in search or expansion flows will be routed through a Reduce Motion-aware decision. When Reduce Motion is enabled, state changes should either avoid animation or use a less dynamic transition.

### 7. Favourite Departure Refresh Concurrency

Favourite departures currently refresh sequentially. Replace that with bounded concurrency so the app can refresh several favourite stops in parallel without spamming the ATP source. The implementation should:

- preserve per-stop mapping of departures
- tolerate individual stop failures without failing the full refresh
- keep ordering stable in the rendered dashboard

### 8. Settings Data-Source Status

Settings diagnostics will evolve from static labels into actual status reporting. Milestone 1 will cover:

- ATP source mode: configured live versus mock/empty behavior
- GTFS presence, current selected resource, last downloaded time, last checked time, update result, and failure message
- AVL endpoint identity
- routing stack summary

This milestone does not yet add a full first-run readiness screen, but it creates the data model and presentation groundwork for Milestone 2.

## Architecture Notes

- Avoid a large pre-emptive refactor before stabilization.
- Add small seams where needed: storage abstraction, nearby-row presentation helper, and settings/source status presentation.
- Preserve current route engine behavior in Milestone 1 except for visibility and refresh improvements.
- Defer major route engine expansion and file decomposition to later milestones where those changes can be verified in context.

## Testing And Verification

Milestone 1 verification will include:

- targeted tests for isolated handoff storage
- updated shared-data tests for deterministic cleanup
- tests for route-option pagination logic where appropriate
- tests for nearby-row distance/ETA formatting if extracted into presentation helpers
- full simulator build
- full simulator test suite

Later milestones will add tests alongside new routing, localization, diagnostics, widget, and notification behavior rather than relying on Milestone 1 coverage.

## Out Of Scope For Milestone 1

Milestone 1 intentionally does not include:

- full first-run readiness UI
- bundled GTFS seed packaging decision
- door-to-door planner and route filters
- transfer reliability modeling
- line detail pages
- disruption-to-route mapping
- commute presets, recents, widget configuration, reminders, or route sharing
- multilingual localization rollout
- the full large-file split

Those remain required by the overall objective and are assigned to later milestones above.
