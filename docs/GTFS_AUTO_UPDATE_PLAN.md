# GTFS Auto-Update Implementation Plan

## Goal

Implement automatic GTFS downloading and updating for the Luxembourg public transport app.

The app should:

1. Fetch metadata from the data.public.lu dataset API.
2. Find the latest GTFS ZIP resource.
3. Compare it with the locally installed GTFS version.
4. Download the ZIP only if needed.
5. Unzip and validate it.
6. Replace the old GTFS atomically.
7. Rebuild the local stop/search index.
8. Keep using the old GTFS if the update fails.

Do not download the GTFS ZIP on every launch.

---

## Dataset

Use this metadata endpoint:

```text
https://data.public.lu/api/1/datasets/5a2a58b9111e9b7f34fc6606/
```

This endpoint returns metadata for the Luxembourg public transport GTFS dataset.

The implementation should inspect the returned JSON `resources` array and choose the newest valid GTFS ZIP resource.

Do not hardcode a dated ZIP filename.

---

## Update Policy

Use this policy:

```text
If no local GTFS exists:
    download latest GTFS immediately

If local GTFS exists:
    check metadata at most once per day

If latest remote resource ID or checksum differs from local metadata:
    download latest GTFS

If download, unzip, validation, or indexing fails:
    keep old local GTFS
```

The update must not block the main app UI.

---

## Files / Modules to Create

Create a clean folder structure.

Suggested files:

```text
Services/GTFS/GTFSUpdateService.swift
Services/GTFS/GTFSMetadataClient.swift
Services/GTFS/GTFSDownloadService.swift
Services/GTFS/GTFSArchiveService.swift
Services/GTFS/GTFSValidator.swift
Services/GTFS/GTFSIndexBuilder.swift
Services/GTFS/Models/DataPublicDataset.swift
Services/GTFS/Models/DataPublicResource.swift
Services/GTFS/Models/LocalGTFSMetadata.swift
Services/GTFS/Mocks/MockGTFSMetadataClient.swift
Services/GTFS/Fixtures/gtfs-dataset-sample.json
Storage/GTFSLocalStore.swift
Tests/GTFSUpdateServiceTests.swift
Tests/GTFSMetadataSelectionTests.swift
Tests/GTFSValidatorTests.swift
```

Do not put the GTFS system into one huge file.

---

## Data Models

Create flexible decodable models for the data.public.lu API.

```swift
struct DataPublicDataset: Decodable {
    let resources: [DataPublicResource]
}

struct DataPublicResource: Decodable, Identifiable {
    let id: String
    let title: String?
    let latest: String?
    let url: String?
    let filetype: String?
    let mime: String?
    let checksum: DataPublicChecksum?
    let lastModified: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case latest
        case url
        case filetype
        case mime
        case checksum
        case lastModified = "last_modified"
    }
}

struct DataPublicChecksum: Decodable {
    let type: String?
    let value: String?
}

struct LocalGTFSMetadata: Codable {
    let resourceId: String
    let title: String
    let checksum: String?
    let lastModified: Date?
    let downloadedAt: Date
    let indexedAt: Date?
}
```

Use flexible ISO-8601 date decoding because the API date format may not exactly match `JSONDecoder` defaults.

---

## Resource Selection Logic

Implement:

```swift
func selectLatestGTFSResource(from dataset: DataPublicDataset) -> DataPublicResource?
```

Rules:

- resource title/name should contain `gtfs`
- resource should be ZIP-like:
  - title ends in `.zip`, or
  - MIME contains `zip`, or
  - filetype is `zip`
- choose newest by `lastModified`
- if dates are missing, use resource order as fallback
- never hardcode the current dated GTFS ZIP filename

---

## Download Decision Logic

Implement:

```swift
func shouldDownload(remote: DataPublicResource, local: LocalGTFSMetadata?) -> Bool
```

Rules:

```text
if local metadata missing → true
if remote resource id differs → true
if remote checksum exists and differs → true
otherwise → false
```

Store `lastMetadataCheckAt` separately so metadata is checked at most once per day.

---

## File Storage

Store GTFS in Application Support.

Suggested paths:

```text
Application Support/
└── GTFS/
    ├── current/
    │   ├── agency.txt
    │   ├── stops.txt
    │   ├── routes.txt
    │   ├── trips.txt
    │   ├── stop_times.txt
    │   └── calendar.txt / calendar_dates.txt
    │
    ├── indexes/
    │   └── stops-index.json or stops.sqlite
    │
    ├── metadata.json
    └── temp/
```

Rules:

- `current/` contains the active usable GTFS.
- `temp/` is used during download/extraction.
- Never delete `current/` until the new GTFS has been downloaded, extracted, validated, and indexed successfully.

---

## Atomic Update Flow

Implement the update flow like this:

```text
1. Fetch dataset metadata.
2. Select latest GTFS ZIP resource.
3. Compare remote resource with local metadata.
4. If unchanged, stop.
5. Download ZIP to temp.
6. Unzip ZIP to temp/extracted.
7. Validate required files.
8. Build new stop/search index from temp/extracted.
9. Move old current/ to backup or delete only after new one is ready.
10. Move temp/extracted to current/.
11. Save metadata.json.
12. Clean temp.
```

If any step fails:

```text
- do not replace current/
- keep using old GTFS
- surface a non-fatal update error
- clean temp if safe
```

---

## GTFS Validation

Create `GTFSValidator`.

Required files:

```text
agency.txt
stops.txt
routes.txt
trips.txt
stop_times.txt
```

At least one of:

```text
calendar.txt
calendar_dates.txt
```

Validation should check:

- required files exist
- required files are not empty
- `stops.txt` contains these columns:
  - `stop_id`
  - `stop_name`
  - `stop_lat`
  - `stop_lon`

Do not perform heavy full-feed validation in MVP.

---

## Stop Index Builder

Create `GTFSIndexBuilder`.

MVP scope:

- parse `stops.txt`
- extract:
  - `stop_id`
  - `stop_name`
  - `stop_lat`
  - `stop_lon`
  - optional `parent_station`
  - optional `wheelchair_boarding`
- build compact searchable local index

Output can be either:

```text
Application Support/GTFS/indexes/stops-index.json
```

or SQLite if the project already uses SQLite.

For MVP, JSON is acceptable if performance is fine.

The app search service should use this index instead of reparsing the full GTFS every time.

---

## Network Behaviour

Use `URLSession`.

Requirements:

- async/await
- timeout configuration
- handle no internet
- handle server errors
- handle malformed JSON
- handle invalid ZIP
- handle disk-space errors if practical
- expose user-safe errors

Do not show raw technical errors to users by default.

---

## User Experience

The GTFS update should be quiet.

Suggested UX:

- On first launch: show normal loading state if GTFS is required for search.
- On later launches: update in the background.
- If update succeeds: silently use new data.
- If update fails: keep old data.
- In Settings → Data Sources, show:
  - current GTFS version/title
  - last downloaded date
  - last metadata check
  - manual “Check for GTFS update” button

Do not interrupt the user with update popups.

---

## Settings Diagnostics

Add a simple diagnostics section if the settings screen exists.

Fields:

```text
GTFS dataset: Luxembourg public transport GTFS
Current resource: <title>
Downloaded: <date>
Last checked: <date>
Checksum: <checksum or unavailable>
Status: Up to date / Update available / Update failed
```

Actions:

```text
Check for update
Redownload GTFS
Clear cached GTFS
```

For MVP, only “Check for update” is required.

---

## Tests

Add tests for:

1. Selecting the latest GTFS resource from controlled dataset JSON fixtures.
2. Ignoring non-GTFS resources.
3. Choosing ZIP resources only.
4. `shouldDownload` returns true when no local metadata exists.
5. `shouldDownload` returns true when resource ID changes.
6. `shouldDownload` returns true when checksum changes.
7. `shouldDownload` returns false when resource ID and checksum match.
8. Validator accepts a minimal valid GTFS folder.
9. Validator rejects missing `stops.txt`.
10. Validator rejects empty required files.
11. Validator rejects `stops.txt` missing required columns.

Use fixtures instead of live network calls in tests.

---

## Acceptance Criteria

The implementation is done when:

- app can fetch data.public.lu dataset metadata
- app can identify the latest GTFS ZIP resource
- app downloads only when needed
- app stores metadata locally
- app unzips into temp directory
- app validates GTFS before replacing old files
- app keeps old GTFS on failure
- app builds a local stops search index
- app does not block the main UI
- tests cover selection, download decision, and validation logic
- code is split into clean files and folders
- no file becomes a giant 1000+ line dump
- project compiles successfully

---

## Constraints

Do not:

- hardcode the current dated GTFS ZIP file
- download the ZIP every launch
- delete old GTFS before validating the new one
- block the main thread
- put all GTFS logic into one huge file
- treat GTFS as live data
- build full route planning from GTFS in MVP
- add a backend
- add accounts or analytics

Do:

- use the metadata API
- compare resource ID/checksum
- update at most once per day automatically
- allow manual refresh from settings later
- keep old data if update fails
- document assumptions
- keep architecture clean
