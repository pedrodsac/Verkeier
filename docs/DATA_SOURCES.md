# Data Sources

The app uses the datasets listed in the PRD and referenced by the LuxDeparture-style use case.

## ATP mobiliteit.lu OpenAPI

Purpose:

- nearby stops
- real-time departures
- delay calculation
- query-time route feasibility, including delayed boardings and transfers

Main endpoints:

- `location.nearbystops`
- `departureBoard`

The verified board contract uses `rtMode=SERVER_DEFAULT` (or `OFF`) and
`passlist=1`, with explicit `date`, `time`, `duration`, and `maxJourneys`.
ATP rejects `FULL`; the relay translates that legacy value for older app
versions and forwards the supported parameters. Per-stop `rtArrDate/Time`,
`rtDepDate/Time`, cancellation, `rtBoarding` and `rtAlighting` are optional.
Missing predictions are never labelled observed. ATP's wall-clock timestamps
in the repeated autumn DST hour are ignored unless a verified offset contract
can identify the intended instant. Bounded boards can truncate;
the routing provider subdivides full intervals and retains partial coverage
when its request or time budget expires.

Implementation rules:

- API key / `accessId` must not be hardcoded or shipped in the app bundle
- route keyed requests through the allowlisted Cloudflare Worker in the `verkeier-relay` repository
- keep upstream credentials in Cloudflare Worker secrets
- app must handle a missing proxy URL gracefully
- see the `verkeier-relay` repository README for setup instructions
- the public dataset lists CC BY 4.0 and directs developers to request a
  personal key from ATP; agree usage, quota, caching, and attribution with ATP
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

Current implementation:

- discover the latest official archive from the data.public.lu dataset API
- download, validate, and install an on-device SQLite database
- retain the last usable feed when an update fails
- use the timetable for offline search, departures, and journey planning

Source:

- `https://data.public.lu/en/datasets/horaires-et-arrets-des-transport-publics-gtfs/`

The dataset is published under CC BY 4.0. The app does not bundle a GTFS
archive; until the first valid download finishes, timetable results are empty.

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

Default MVP feed:

- `https://web.vdl.lu/autobus/data/messages/messages.xml`

The dataset is published by Ville de Luxembourg as "Mobilité - AVL Autobus" on data.public.lu. The XML contains `Message` records with start/end dates, urgency/category, titles/text, and affected line/stop elements.
The dataset page lists CC0.

## MapKit / Apple Maps

Purpose:

- map UI
- user location
- stop markers
- route display
- Apple Maps transit handoff
- local search/geocoding where useful

Important:

MapKit provides map presentation, search, Apple Maps handoff, and road geometry.
MobiliteitKit performs on-device public-transport routing from immutable GTFS,
with ATP HAFAS data applied as a query-time realtime overlay. HAFAS does not
replace or mutate the installed GTFS timetable; missing, failed, or ambiguous
live data falls back to scheduled routing.

Do not claim Apple Maps exposes all live transit data as raw API data.

## JCDecaux vel’OH! bike sharing

Purpose:

- static Luxembourg City station identities and coordinates
- live station status, available bikes, and free docking stands
- route-planner bike legs before, after, or between public-transport legs

Sources:

- static stations: `https://developer.jcdecaux.com/rest/vls/stations/luxembourg.csv`
- dynamic stations: `https://api.jcdecaux.com/vls/v1/stations?contract=luxembourg`

Implementation rules:

- refresh the 12 KB static CSV at app startup and retain the last valid snapshot
- refresh dynamic availability when calculating or explicitly refreshing a route
- route the dynamic request through the Cloudflare Worker; never commit or log the API key
- zero or unknown bike/dock counts remain selectable but are shown as warnings
- MapKit walking geometry is used as a documented bicycle-path approximation;
  bicycle duration uses a 15 km/h estimate plus pickup/return overhead
