# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Verkéier is a native SwiftUI iOS app for Luxembourg public transport, built to feel like Apple Maps (full-screen MapKit map with a persistent draggable bottom sheet). It is being built in phases from the design documents in `docs/`. Treat it as a serious maintainable project, not a prototype.

## Commands

Build for simulator:

```sh
xcodebuild -project Verkéier.xcodeproj -scheme Verkéier -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Run the full test suite:

```sh
xcodebuild -project Verkéier.xcodeproj -scheme Verkéier -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Run a single test class or method (Swift Testing):

```sh
xcodebuild -project Verkéier.xcodeproj -scheme Verkéier -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:VerkéierTests/GTFSValidatorTests
```

Regenerate the bundled GTFS resource from a downloaded feed (use `--max-stops` for small fixtures):

```sh
python3 Scripts/preprocess_gtfs.py ~/Downloads/gtfs.zip Verkéier/Resources/gtfs-compact.json
```

Local config (git-ignored; holds `ATP_ACCESS_ID` and an optional `AVL_MESSAGES_URL` override):

```sh
cp Config/LocalConfig.xcconfig.example Config/LocalConfig.xcconfig
```

## Architecture

Strict layering, enforced top-to-bottom — never short-circuit it:

```
SwiftUI View → ViewModel/Observable State → Service Protocol → API Client/Storage → Decoder/Mapper → Domain Model
```

- **No networking or business logic in views or view bodies.** Route everything through view models and injected services.
- **Every service is a protocol** with multiple implementations: `Live*` (production), `*Mock`/`Empty*` (previews/tests), and often `Local*` (on-device data). E.g. `ATPClient` has `LiveATPClient`, `ATPMockClient`, `EmptyATPClient`.
- **Dependency injection is via SwiftUI `EnvironmentValues`** using `@Entry` (see `Verkéier/App/AppDependencies.swift`). Each service has a default value there; views read it with `@Environment(\.serviceName)`. Override the environment to inject mocks in previews/tests.
- UI must be previewable with mock data; API/parsing code must be testable without UI.

### Module layout

- `Verkéier/App/` — entry point (`VerkéierApp`), config (`AppConfiguration`), DI (`AppDependencies`), SwiftData container, debug data fixtures/modes.
- `Verkéier/Features/<Domain>/` — feature UI grouped as `Views/`, `ViewModels/`, `Components/`. Domains: `Map`, `BottomSheet`, `Stops`, `Departures`, `Search`, `Routes`, `Favourites`, `Alerts`, `Settings`, `LiveActivities`, `AppIntents`.
- `Verkéier/Services/` — `ATP/` (mobiliteit.lu OpenAPI departures/nearby stops), `GTFS/` (local stop search, timetable index, download/update/validation pipeline, offline schedules), `AVL/` (Ville de Luxembourg alerts XML), `Location/`, `Routing/` (MapKit route + Apple Maps handoff, public-transport route service), `Notifications/`.
- `Verkéier/Models/` — typed domain models (`Stop`, `Departure`, `RoutePlan`, `AlertMessage`, etc.).
- `Verkéier/Storage/` — SwiftData persistence (e.g. favourites).
- `VerkéierShared/` + `VerkéierWidgets/` — shared widget/Live Activity types and the WidgetKit extension (separate `VerkéierWidgets` scheme/target).
- `VerkéierTests/` — Swift Testing suites, named after the unit under test (`ATPMapperTests`, `GTFSValidatorTests`).

### Data sources & external assumptions

ATP (mobiliteit.lu) access is gated behind `ATP_ACCESS_ID`; the app tolerates a missing id during early phases (`EmptyATPClient`). When an external API contract is uncertain, add a `TODO` rather than guessing. See `docs/DATA_SOURCES.md` and `docs/ARCHITECTURE.md` for the source of truth on contracts.

## Conventions

- Swift Testing only: `@Test` / `#expect`. No live network in tests — use fixtures, mocks, and temp directories. Add tests beside the existing suite for the unit.
- Keep most files under ~300–400 lines. Split large views into subviews; split large services into client/decoder/mapper/mock/fixtures.
- async/await + typed models over ad-hoc dictionaries or string parsing.
- Keep new files inside the relevant feature/layer folder — **no root-level source files**.
- Support Dynamic Type and VoiceOver; handle loading, empty, error, stale, and offline states.

## Hard rules

- Never hardcode API keys, ATP access ids, or dated production GTFS ZIP URLs. `Config/LocalConfig.xcconfig` stays local and ignored.
- Never present hardcoded fake data as production data.
- Do not remove attribution/legal/privacy screens, and never imply the app is an official Luxembourg public transport product.
- Do not add accounts, ads, subscriptions, or a backend unless explicitly requested.

## Working notes

- Make occasional small, focused commits after a coherent buildable change or passing-test milestone; don't mix unrelated work. Use concise imperative messages (`Add GTFS update validation`).
- `docs/` holds the phased plan (`PRD.md`, `ARCHITECTURE.md`, `MVP_CHECKLIST.md`, `CODEBASE_RULES.md`, feature/audit specs). Start with `docs/README.md` for navigation and `docs/SERVICES.md` for protocol signatures. Consult both before large changes — they define intended scope and contracts.

## Skills & tooling

Installed skills cover the SwiftUI/iOS surface this project lives in — use the matching one when doing that kind of work:

- **SwiftUI:** `swiftui-pro` / `swiftui-expert-skill` (review, modern APIs, data flow), `swiftui-animation` (transitions, springs, SF Symbol effects), `swiftui-performance-audit` (janky scroll, excess view updates), `make-interfaces-feel-better` (UI polish, micro-interactions).
- **Platform:** `ios-accessibility` (VoiceOver, Dynamic Type — see the Dynamic Type/VoiceOver convention above), `ios-localization` (String Catalogs), `ios-networking` (URLSession for the ATP/AVL/GTFS clients), `swiftdata-pro` (favourites storage).
- **Testing:** `swift-testing-pro`, `swift-protocol-di-testing` — match the Swift Testing + protocol-DI conventions this codebase already uses.
- **Build/run:** `xcodebuildmcp-cli`, `ios-simulator-skill` for building, running, and UI automation on the simulator.

## Codebase graph

`graphify-out/` holds a knowledge graph of the codebase — `GRAPH_REPORT.md` (god nodes, communities, surprising connections, file-size/god-object hints) and `graph.html` (interactive map). Skim the report to orient on unfamiliar areas or spot over-connected god objects before a large change. Refresh after structural changes with `/graphify . --update` (code-only diffs cost no LLM tokens); ask a question against it with `/graphify query "..."`.
