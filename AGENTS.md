# Repository Guidelines

## Project Structure & Module Organization

LuxTransit is a native SwiftUI iOS app. App source lives in `LuxTransit/`, with clear feature and service boundaries:

- `LuxTransit/App/`: app entry point, configuration, and dependency injection.
- `LuxTransit/Features/`: SwiftUI feature UI, grouped by domain such as `Map`, `Stops`, `Search`, `Settings`, and `Favourites`.
- `LuxTransit/Services/`: API clients and service-layer logic for ATP, GTFS, AVL, routing, and location.
- `LuxTransit/Models/`: shared domain models.
- `LuxTransit/Storage/`: persistence and local file storage helpers.
- `LuxTransit/Resources/`: bundled fixtures and app resources.
- `LuxTransitTests/`: Swift Testing unit tests.
- `LuxTransitWidgets/` and `LuxTransitShared/`: WidgetKit extension and shared widget/activity types.

Keep new files inside the relevant feature or layer. Do not add root-level source files.

## Build, Test, and Development Commands

Build the app for an iOS simulator:

```sh
xcodebuild -project LuxTransit.xcodeproj -scheme LuxTransit -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Run the test suite:

```sh
xcodebuild -project LuxTransit.xcodeproj -scheme LuxTransit -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Create local configuration when needed:

```sh
cp Config/LocalConfig.xcconfig.example Config/LocalConfig.xcconfig
```

Generate a compact GTFS resource from a downloaded feed:

```sh
python3 Scripts/preprocess_gtfs.py ~/Downloads/gtfs.zip LuxTransit/Resources/gtfs-compact.json
```

## Coding Style & Naming Conventions

Use Swift conventions: 4-space indentation, `UpperCamelCase` for types, `lowerCamelCase` for properties and methods. Prefer small Swift files under roughly 300-400 lines. Keep networking out of SwiftUI views; route UI actions through view models, services, or injected dependencies. Use async/await and typed models instead of ad hoc dictionaries or string parsing where practical.

## Testing Guidelines

Tests use Swift Testing with `@Test` and `#expect`. Add focused tests beside related existing suites in `LuxTransitTests/`, using names like `GTFSValidatorTests` or `ATPMapperTests`. Avoid live network calls in tests; use fixtures, mocks, and temporary directories.

## Commit & Pull Request Guidelines

Git history currently only shows `Initial Commit`, so use concise imperative commit messages such as `Add GTFS update validation`. Pull requests should include a short summary, test results, linked issue or task when available, and screenshots for visible UI changes.

## Security & Configuration Tips

Never hardcode API keys, ATP access IDs, or dated production GTFS ZIP URLs. Keep `Config/LocalConfig.xcconfig` local and ignored. Preserve attribution and do not imply the app is an official Luxembourg public transport product.

## Agent-Specific Instructions

When working as an agent in this repository, make occasional focused commits even when not explicitly prompted, especially after a coherent buildable change or passing test milestone. Keep commits small, intentional, and avoid mixing unrelated work.
