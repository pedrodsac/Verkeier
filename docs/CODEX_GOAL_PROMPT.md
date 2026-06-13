/goal

You are GPT-5.5. Act as lead architect, senior iOS engineer, and reviewer.

Build the iOS app described in `docs/PRD.md`.

Also read and follow:

- `docs/ARCHITECTURE.md`
- `docs/CODEBASE_RULES.md`
- `docs/DATA_SOURCES.md`
- `docs/SUBAGENT_POLICY.md`
- `docs/MVP_CHECKLIST.md`

The app must be a native iOS Luxembourg public transport app using SwiftUI, MapKit, Core Location, SwiftData, ActivityKit, App Intents, WidgetKit, ATP mobiliteit.lu OpenAPI, GTFS, and AVL data.

Main UX requirement:

- full-screen MapKit map
- Apple Maps-style persistent draggable bottom sheet
- native SwiftUI interface
- nearby stops
- live departures
- delay display
- favourites
- route planning with MapKit / Apple Maps handoff
- Live Activities
- App Intents
- widgets if feasible
- attribution/legal screen

Work in phases. Do not build everything in one pass.

First:

1. Inspect the repo.
2. Read all files in `docs/`.
3. Summarise the implementation plan.
4. Implement only Phase 1 and Phase 2 from `docs/MVP_CHECKLIST.md`.
5. Build the project.
6. Fix compiler errors.
7. Stop and report what changed.

Use subagents according to `docs/SUBAGENT_POLICY.md`.

Do not create a messy prototype. This must be a serious maintainable codebase with a clean folder structure.
