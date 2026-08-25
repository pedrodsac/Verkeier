# Verkéier

Verkéier is a native SwiftUI iOS app for Luxembourg public transport. The codebase is being built in phases from the documents in `docs/`.

## Current Phase

Implemented:

- map-first SwiftUI shell with persistent bottom sheet
- nearby stops and live departures through ATP client abstractions
- GTFS local stop search
- SwiftData favourites
- MapKit route calculation and Apple Maps handoff
- AVL alerts from the Ville de Luxembourg messages XML feed
- Live Activity tracking infrastructure
- App Intents and favourite stop App Entities
- WidgetKit extension with favourite, departures, and Live Activity widgets
- settings, attribution, privacy, and diagnostics screen

Not implemented yet:

- production ATP access-id confirmation, proxy quotas, and exact attribution wording
- full production GTFS preprocessing pipeline
- broad manual QA across all simulator/device surfaces

## Local Configuration

Copy the example config and provide local values when data-source phases need them:

```sh
cp Config/LocalConfig.xcconfig.example Config/LocalConfig.xcconfig
```

`Config/LocalConfig.xcconfig` is ignored by git and must not contain committed secrets.

Required later:

- `API_PROXY_URL`: deployed Cloudflare Worker URL for keyed ATP and JCDecaux requests
- `AVL_MESSAGES_URL`: optional override for the Ville de Luxembourg AVL messages XML feed

The upstream ATP and JCDecaux credentials belong in the Worker’s Cloudflare
secrets, not in the iOS build settings or app bundle. The app handles a
missing proxy URL during early phases.

See the [verkeier-relay repository](https://github.com/pedrodsac/verkeier-relay)
for local development and deploy instructions.

## Build

Open `Verkéier.xcodeproj` in Xcode or build from the command line:

```sh
xcodebuild -project Verkéier.xcodeproj -scheme Verkéier -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## GTFS Preprocessing

Download the current Luxembourg GTFS ZIP from data.public.lu, then generate a compact app resource:

```sh
python3 Scripts/preprocess_gtfs.py ~/Downloads/gtfs.zip Verkéier/Resources/gtfs-compact.json
```

Use `--max-stops` when producing a small fixture. Do not commit oversized generated feeds without checking app size and update cadence.

## Data Attribution Placeholder

Transport data:

- Administration des transports publics - mobiliteit.lu OpenAPI
- Administration des transports publics - GTFS public transport schedules and stops
- Ville de Luxembourg - AVL Autobus

Maps:

- Apple Maps / MapKit

Replace this placeholder with exact wording after ATP confirmation.
