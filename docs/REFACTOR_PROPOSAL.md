# Refactor proposal: views and structure

Status: **approved** (2026-10-14). Work happens on the `refactor/views-and-structure`
branch.

Goal: the same app with the same behaviour and the same look, but with code that is
uniform, easy to read and easy to navigate. Widgets and Live Activities are left
alone for now.

---

## 1. The main problem: values passed down through every level

### Today

```
TransitMapViewModel          one object, 11 files, ~1,500 lines, holds everything
        │  copied on every redraw into
        ▼
TransitSheetPresentationModel  (11 snapshot structs)
  + TransitSheetActions        (40 closures)
        │  passed to
        ▼
TransitBottomSheet ──► BottomSheetContent / TransitSheetDestinationView
        │  sliced again into
        ▼
SearchActions, RouteActions, StopDetailActions, LineDetailActions, FavouritesActions …
        │  passed to
        ▼
every screen ──► every component
```

Adding one button to a screen today means editing four or five files just to pass
a value and a closure down to it.

### Proposed

```
A few small feature models, created once at the top and put in the environment:

  MapModel · StopDetailModel · RoutePlannerModel · SearchModel
  HomeModel · AlertsModel · SheetRouter (navigation)

        │  each screen reads only the one it needs
        ▼
StopDetailScreen:   @Environment(StopDetailModel.self) private var model
        │  components get plain values only
        ▼
DepartureRow(departure: departure)
```

- Actions become **methods on the model** (`model.toggleFavourite()`), not closures
  passed through every level.
- All `…PresentationModel` and `…Actions` types are **removed**.
- `TransitMapViewModel` is **split** into the feature models above, each a separate type
  (not more extension files of the same type).

### Rules

- A **screen** takes at most one parameter (what to show, such as a `Stop`) and reads
  its model from the environment.
- A **component** (row, card, badge) takes the plain values it displays plus the
  actions it triggers. Components never read feature models, so they are easy to
  preview with fixture data.

---

## 2. Naming

One suffix per role, used everywhere:

| Suffix | Meaning | Example |
|---|---|---|
| `Screen` | A full page: a tab root or something you navigate to | `StopDetailScreen` |
| `Sheet` | Something presented on top as a sheet | `MainSheet`, `FavouriteEditorSheet` |
| `Section` | A block inside a screen | `DisruptionsSection` |
| `Card` | A self-contained boxed block | `RouteOptionCard` |
| `Row` | One item in a list | `DepartureRow`, `StopRow` |
| `Badge` | A small inline label or pill | `LineBadge` |
| `Button` | A button | `PlanningTimeButton` |
| `Model` | An `@Observable` class with a feature's state and actions | `StopDetailModel` |

These go away: the `View` suffix on SwiftUI views (kept only for UIKit wrappers),
`Content`, `Panel`, `Layer`, `Destination`, `Presentation`, `ViewModel`, and the
`Transit` prefix (the whole app is about transit, so it adds nothing).

### Main renames

| Today | Proposed | Note |
|---|---|---|
| `LaunchGateView` | `RootScreen` | Chooses between the map and route preparation |
| `RoutingOptimisationScreen` | `RoutePreparationScreen` | Matches what the UI calls it |
| `TransitMapScreen` (+ 4 extension files) | `MapScreen` | Logic moves into models |
| `TransitMapLayer` | folded into `MapScreen` | It only converts model data for the map |
| `TransitMapView` | `StopsMapView` | UIKit wrapper, so it keeps `View` |
| `TransitBottomSheet` | `MainSheet` | The Home / Plan / Settings tabs |
| `TransitSheetDestinationView` | `SheetDestinations` | Shrinks to one line per destination |
| `BottomSheetContent` + `CommuteDashboardView` | `HomeScreen` | The Home tab |
| `SearchResultsContent` (in `SearchView.swift`) | `SearchScreen` | |
| `PlanView` + `RouteView` | `RoutePlannerScreen` | `PlanView` only wraps `RouteView` |
| `RouteTimelineView` | `RouteTimelineScreen` | |
| `RoutePlaceSearchView` | `PlaceSearchScreen` | |
| `TripDetailView` + `DepartureTripDestination` | `TripDetailScreen` | The second one is only its loading state |
| `LineDetailView` | `LineDetailScreen` | |
| `StopDetailView` | `StopDetailScreen` | |
| `StopGroupView` | `StopGroupScreen` | |
| `AlertsView` | `AlertsScreen` | |
| `SettingsView`, `SettingsAboutView`, `SettingsAdvancedView`, `SettingsOpenSourceView` | `SettingsScreen`, `AboutScreen`, `AdvancedSettingsScreen`, `OpenSourceScreen` | |
| `FavouriteCustomizerView` | `FavouriteEditorSheet` | |
| `DepartureListRow` | `DepartureRow` | |
| `RouteChip`, `TransitBadge`, `TimelineLineBadge`, `TimelineTransitBadge`, `RouteLineCard` | one `LineBadge` | These are near copies of each other today |
| `NearbyStopsView`, `PlaceholderPanel` | deleted | Only used by their own previews |

Files that hold several views today (`StopDetailHeader.swift` has 5,
`StopDetailSections.swift` has 5, `RouteSupportingViews.swift` has 4) are split so each
view has its own file.

---

## 3. How every view file looks

```swift
import SwiftUI

/// Shows the next departures and details for one stop.
struct StopDetailScreen: View {
    @Environment(StopDetailModel.self) private var model

    let stop: Stop

    @State private var isEditingFavourite = false

    var body: some View {
        List {
            header
            departures
        }
        .navigationTitle(stop.displayName)
        .toolbar { toolbarContent }
        .sheet(isPresented: $isEditingFavourite) { FavouriteEditorSheet(stop: stop) }
        .task(id: stop.id) { await model.load(stop) }
    }
}

// MARK: - Subviews

private extension StopDetailScreen {
    var header: some View { … }
    var departures: some View { … }
    var toolbarContent: some ToolbarContent { … }
}

#Preview {
    StopDetailScreen(stop: .preview)
        .environment(StopDetailModel.preview)
}
```

Rules:

- One main view per file, and the file is named after it. Tiny `private` helpers may
  share the file.
- The same order everywhere: environment, inputs, state, `body`, subviews, helpers,
  preview.
- `body` stays short (about 30 lines). Bigger pieces become private subviews or their
  own component.
- All `@State` properties and helpers are `private`.
- No `+Actions` or `+Presentation` extension files for views.
- No formatting or business logic in views (for example, building the "share
  departures" text moves into the model or a formatter).
- Modifiers in a fixed order: layout and style, then navigation (title, toolbar),
  then presentation (sheet, alert), then lifecycle (`task`, `onChange`).
- 4 spaces, no tabs, enforced by the formatter (see question 3).
- Every screen and component has a `#Preview` with fixture data.

---

## 4. Folders

```
Features/
  Root/        RootScreen, RoutePreparationScreen
  Map/         MapScreen, StopsMapView, map annotations
  Sheet/       MainSheet, SheetDestinations, SheetRouter
  Home/        HomeScreen, favourites components, FavouriteEditorSheet
  Stops/       StopDetailScreen, StopGroupScreen, DepartureRow, …
  Routes/      RoutePlannerScreen, RouteTimelineScreen, TripDetailScreen, LineDetailScreen, …
  Search/      SearchScreen, PlaceSearchScreen
  Alerts/      AlertsScreen
  Settings/    SettingsScreen, AboutScreen, AdvancedSettingsScreen, OpenSourceScreen
  Shared/      Components used by more than one feature (LineBadge, CardSurface, …)
```

Inside each feature: `Screens/`, `Components/` and `Models/`. No loose files at the
feature root (today `RoutePresentation.swift`, `StopDetailPresentation.swift` and others
sit there).

`AppIntents/` and `LiveActivities/` stay as they are.

---

## 5. Order of work

Every step builds, passes the tests, and gets its own commit, so any step can be
reviewed or undone on its own.

1. **Formatting only:** run the formatter over the app. No code changes.
2. **Delete unused views:** `NearbyStopsView`, `PlaceholderPanel` and their models.
3. **Create the feature models** by splitting `TransitMapViewModel`, and put them in the
   environment.
4. **Move screens onto their model** one at a time, removing the
   `…PresentationModel` / `…Actions` plumbing as each one moves: Settings, Alerts,
   Search, Stops, Routes, Home, then Map.
5. **Rename** types, files and folders.
6. **Merge the duplicate badges** and split files that hold several views.
7. **Update `AGENTS.md`** with these rules so new code follows them.

After each step: build, run the tests, and check the affected screens in the
simulator.

This is a large change (about 60 view files and most of the feature folders). I expect
it to take several sessions.

---

## Questions for you

1. **`Model` or `ViewModel`?** I suggest `StopDetailModel` (shorter, and it pairs with
   `StopDetailScreen`). `AGENTS.md` currently says `ViewModel`.
2. **Drop the `Transit` prefix?** I suggest yes.
3. **Formatter:** the repo already has a `.swiftformat` config, but SwiftFormat isn't
   installed on this Mac, which is how tabs and spaces got mixed. Either you install it
   (`brew install swiftformat`), or I switch to Xcode's built-in `swift-format`, which
   needs no install.
