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

Release work remains for data-provider approval, relay quotas, privacy disclosures,
and device QA. See `docs/DATA_SOURCES.md` for the current data contracts.

## Local Configuration

Copy the example config and set the URL of a relay you operate:

```sh
cp Config/LocalConfig.xcconfig.example Config/LocalConfig.xcconfig
```

`Config/LocalConfig.xcconfig` is ignored by Git and is optionally included by
`Config/AppConfig.xcconfig`. A fresh checkout has no relay URL, so live ATP
departures and dynamic bike availability are unavailable until one is set.

- `API_PROXY_URL`: HTTPS URL of your deployed Cloudflare Worker for keyed ATP
  and JCDecaux requests
- `AVL_MESSAGES_URL`: optional override for the public AVL messages XML feed

The upstream ATP and JCDecaux credentials belong in the Worker's Cloudflare
secrets, never in iOS build settings or the app bundle. The relay URL itself
is visible to anyone using the app. Protect its quota before distributing a
build that points at it.

See the [verkeier-relay repository](https://github.com/pedrodsac/verkeier-relay)
for local development and deploy instructions.

## Bundled offline walking graph

Before making a release with offline walking routes, generate the Luxembourg
Valhalla archive and its checked manifest locally:

```sh
Scripts/build_luxembourg_routing_dataset.sh
```

The script downloads the public Geofabrik Luxembourg OpenStreetMap extract and
uses Valhalla 3.6.3 in Docker. It writes `luxembourg-walking-tiles.tar` and
`luxembourg-walking-manifest.json` to `Verkéier/Resources/`; Xcode bundles
those resources automatically. The archive is installed into Application
Support and validated on the first app launch. Regenerate it for each release
when map data should be refreshed.

## Build

Open `Verkeier.xcodeproj` in Xcode or build from the command line:

```sh
xcodebuild -project Verkeier.xcodeproj -scheme Verkeier -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## GTFS Preprocessing

The app downloads the current Luxembourg GTFS archive from data.public.lu and
builds its on-device database. No GTFS archive is bundled with this repository.

## Data Attribution

Transport data:

- [ATP mobiliteit.lu OpenAPI](https://data.public.lu/en/datasets/api-mobiliteit-lu/)
  and [ATP GTFS schedules](https://data.public.lu/en/datasets/horaires-et-arrets-des-transport-publics-gtfs/): CC BY 4.0; credit Administration des transports publics and link to the source and license when redistributing derived data.
- [Ville de Luxembourg AVL Autobus](https://data.public.lu/en/datasets/mobilite-avl-autobus/): CC0.
- JCDecaux vel'OH! station data: subject to the provider's API terms.

Maps:

- Apple Maps / MapKit
- [OpenStreetMap](https://www.openstreetmap.org/copyright) walking graph data: ODbL; credit OpenStreetMap contributors.

The app is independent and is not affiliated with Luxembourg's transport
operators. Original source code, documentation, and app icon artwork in this
repository are available under the [MIT license](LICENSE). Third-party
packages and transport or map data retain their own licenses and terms.
