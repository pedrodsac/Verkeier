# Data Sources

The app uses the datasets listed in the PRD and referenced by the LuxDeparture-style use case.

## ATP mobiliteit.lu OpenAPI

Purpose:

- nearby stops
- real-time departures
- delay calculation

Main endpoints:

- `location.nearbystops`
- `departureBoard`

Implementation rules:

- API key / `accessId` must not be hardcoded
- use an ignored local config file, `.xcconfig`, or another safe placeholder
- app must handle missing key gracefully
- add setup instructions
- add mock fixtures for development and tests
- mark uncertain response fields with TODOs
- do not invent live status

Before release, ATP must confirm:

- commercial use
- key exposure in a public iOS app
- quotas/rate limits
- caching rules
- attribution text

## GTFS

Purpose:

- static stop database
- stop names and coordinates
- route/line/operator metadata
- local stop search
- scheduled fallback where practical

MVP approach:

- use preprocessed local JSON or SQLite
- sample/mock data is acceptable until real feed processing is added
- do not build full GTFS journey planning in MVP unless simple and reliable

## AVL Autobus

Purpose:

- Luxembourg City bus messages
- alerts/disruptions
- optional line/stop messages

Implementation rules:

- fetch and parse XML/GeoJSON where needed
- handle empty or malformed data safely
- show source attribution
- if mapping alerts to stops/lines is uncertain, show general alerts first

## MapKit / Apple Maps

Purpose:

- map UI
- user location
- stop markers
- route display
- Apple Maps transit handoff
- local search/geocoding where useful

Important:

MapKit is the visual/routing layer. ATP is the live departure layer.

Do not claim ATP provides full route planning.
Do not claim Apple Maps exposes all live transit data as raw API data.
