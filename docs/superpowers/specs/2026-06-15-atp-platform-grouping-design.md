# ATP Platform Grouping and Combined Departures

## Goal

Mobiliteit ATP returns each platform as a separate stop. LuxTransit should present those platform-level results as one user-facing stop per station and show a combined live departure board for all platforms in that station.

## Approach

The app-facing `Stop` model will carry the platform-level ATP identifiers needed for live departure requests:

- `id` remains the stable identifier used by the UI and favourites.
- `platformIds` stores the underlying ATP stop IDs to query for live departures.
- Existing GTFS and local stops default `platformIds` to `[id]`.

`ATPMapper.mapNearbyStops` will group ATP `StopLocation` values by normalized locality and cleaned stop name. Each grouped stop will merge transport modes, choose a representative location from the grouped platforms, and preserve every platform `extId` or `id` in `platformIds`.

## Departure Flow

`ATPClient` will expose a combined board request for multiple stop IDs. `LiveATPClient` will fetch each platform board, merge the results, remove duplicate departures when ATP returns the same journey from multiple platform IDs, and sort by realtime then scheduled departure.

Selected stop details and favourite departure refreshes will call the combined-board API with `stop.platformIds`, so the UI continues to show a single board for the grouped stop.

## Persistence

Favourites will persist `platformIds` alongside the existing stop fields. Older stored favourites without platform IDs will fall back to `[stopId]`, preserving current data.

## Errors

If every platform board request fails, the caller should treat the combined request as failed. If at least one platform succeeds, show the successful departures and avoid failing the whole station board.

## Tests

Add focused tests for:

- ATP nearby-stop grouping across multiple platform IDs with the same station name.
- Combined departure requests merging and sorting results from multiple platform IDs.
- Favourite persistence round-tripping `platformIds` and falling back for older records.
