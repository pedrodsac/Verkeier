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

Source:

- `https://data.public.lu/en/datasets/horaires-et-arrets-des-transport-publics-gtfs/`

The current dataset page exposes dated ZIP resources such as:

- `https://download.data.public.lu/resources/horaires-et-arrets-des-transport-publics-gtfs/20260610-065644/gtfs-20260609-20260823.zip`

Preprocessing:

```sh
python3 Scripts/preprocess_gtfs.py /path/to/gtfs.zip Verkéier/Resources/gtfs-compact.json
```

The app loads cached/generated GTFS data when available. It does not fall back to bundled sample stops; if no GTFS data has been fetched or bundled, GTFS stop results remain empty.

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
- keep the API key in ignored local build configuration; never commit or log it
- zero or unknown bike/dock counts remain selectable but are shown as warnings
- MapKit walking geometry is used as a documented bicycle-path approximation;
  bicycle duration uses a 15 km/h estimate plus pickup/return overhead
