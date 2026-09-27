# Architecture

Verkéier is a native SwiftUI iOS app with a full-screen MapKit map and a
persistent bottom sheet. Features use observable state and injected services;
networking and feed parsing stay out of view bodies.

```text
SwiftUI View → Observable State → Service Protocol → API Client or Storage
             → Decoder / Mapper → Domain Model
```

## Targets and folders

- `Verkeier.xcodeproj` contains the `Verkeier` app, `VerkeierWidgets` extension,
  and `VerkeierTests` target. The source folders retain the product name's
  accent (`Verkéier/`, `VerkéierWidgets/`, `VerkéierShared/`).
- `Verkéier/App/` wires runtime configuration, service defaults, persistence,
  and the app entry point.
- `Verkéier/Features/` groups SwiftUI views, view models, and components by
  feature.
- `Verkéier/Services/Transit/` owns GTFS installation and offline queries,
  plus the app adapter around MobiliteitKit's typed HAFAS client.
- `Verkéier/Services/Routing/` plans transit journeys and walking routes.
- `Verkéier/Services/AVL/` reads Ville de Luxembourg disruption messages.
- `Verkéier/Services/Location/` and `Verkéier/Services/Notifications/` isolate
  platform APIs.
- `Verkéier/Models/` and `Verkéier/Storage/` hold domain types and local data.

## Data flow

The app reads `API_PROXY_URL` from its Info.plist build setting. When set,
`MobiliteitLiveTransitService` sends nearby-stop and departure-board requests
to the allowlisted `verkeier-relay` Worker. That Worker owns the ATP credential.
The same client supplies optional realtime observations for journey planning.
Without a relay URL, live transit is unavailable and scheduled routing can
still use an installed GTFS database.

`MobiliteitGTFSService` discovers the current official feed on data.public.lu,
downloads and validates it, then installs an on-device database. The app does
not bundle a production GTFS archive. The last usable feed remains available
when an update fails. `MobiliteitRouteService` routes over that local feed and
applies verified realtime observations at query time. Walking geometry uses a
local graph when installed and MapKit where needed.

The app calls the public AVL XML feed and JCDecaux static station feed
directly. Dynamic bike-share availability goes through the relay when
configured. MapKit provides map display, place search, and Apple Maps handoff.

## Dependency injection

`Verkéier/App/AppDependencies.swift` declares `EnvironmentValues` entries.
`Verkéier/App/VerkéierApp.swift` injects live implementations into the app
scene. Previews and tests supply fixture or unavailable implementations.
Current protocol signatures and implementations are summarized in
`docs/SERVICES.md`; the Swift source is authoritative.

## Rules

- Keep business logic and networking in injected services or view models.
- Use typed domain models and async/await.
- Make loading, empty, error, stale, and offline states visible to users.
- Never ship provider credentials or fake production data in the app bundle.
- Keep attribution and the independent-app notice visible.
