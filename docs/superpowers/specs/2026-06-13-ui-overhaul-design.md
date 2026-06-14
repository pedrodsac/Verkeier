# LuxTransit UI Overhaul Design

Date: 2026-06-13

## Goal

Redesign LuxTransit from a visible feature-section shell into an Apple Maps-like, contextual transit experience. The app should feel native, intuitive, and useful immediately, with the full-screen map preserved as the permanent background.

Primary outcomes:

- Reduce taps for daily commute actions.
- Remove the fixed bottom-sheet section menu feeling.
- Prioritize favourites and next departures on launch.
- Keep the interface uncluttered while preserving search, stop details, routes, alerts, settings, and location controls.
- Use system materials, SF Symbols, and native SwiftUI/MapKit patterns with subtle Luxembourg transit identity.

## Product Direction

The chosen direction is **Commute Dashboard**.

The app opens to a favourites-first commute view over a full-screen map. The UI should resemble Apple Maps in structure: floating search at the top, lightweight map controls, and a contextual bottom sheet that changes according to what the user is doing.

LuxTransit should not feel like a collection of tabs or demo panels. The user should primarily interact by searching, tapping the map, selecting a stop, expanding commute cards, or opening contextual actions.

## App Shell and Navigation

### Map Background

The full-screen `Map` remains the visual foundation. Stop markers, favourite markers, selected-stop state, user location, and route overlays continue to live on the map.

### Floating Controls

The redesign introduces Apple Maps-style floating controls:

- A top search pill for stop search.
- A compact alert badge/button near the search area when alerts are relevant.
- A location recenter button.
- An overflow/settings control for secondary app information, attribution, privacy, and diagnostics.

These controls should use SF Symbols and system materials. They should be visually quiet and avoid competing with the bottom sheet.

### Contextual Sheet States

Replace the user-facing `BottomSheetMode` section picker with contextual sheet state. Proposed states:

- `home`
- `search`
- `stopDetail(stop)`
- `directions(stop)`
- `alerts`
- `settings`

The user should not have to choose between Nearby, Search, Stop, Route, Favourites, Alerts, and Settings from a main menu. The app should choose the correct sheet context based on the user action.

State transitions:

- App launch -> `home`.
- Tap search pill -> `search`.
- Select search result, map marker, nearby suggestion, or favourite -> `stopDetail(stop)`.
- Tap Directions on selected stop -> `directions(stop)`.
- Tap alert badge or compact alert row -> `alerts`.
- Tap overflow/settings -> `settings`.

## Commute Home Sheet

The home sheet is a **Commute Dashboard**.

### With Favourites

Default home content:

- Title: `Commute`.
- Short status text, such as `Updated 08:42` or `Live departures from favourites`.
- Compact grouped cards for favourite stops.
- A compact alert row only when active or high-priority alerts are relevant.

Each favourite stop card is collapsed by default and shows:

- Stop name.
- Locality when available.
- Mode or route indicators using SF Symbols and line-color pills.
- One concise summary of the most useful next departure.
- A secondary departure line when space allows.
- A disclosure affordance for expansion.

Expanded favourite cards show the top 2-3 departures inline. Tapping the stop title/card opens the selected stop sheet. Tapping a departure may either open the stop detail focused around that departure or expose tracking, depending on implementation simplicity.

### Without Favourites

When the user has no saved stops, the home sheet becomes a minimal get-started state:

- The top search pill remains primary.
- Sheet title becomes `Get Started` or similar.
- Show 3-5 nearby stop suggestions.
- Each suggestion should make it clear that selecting a stop can lead to saving it as a favourite.
- Avoid a multi-step onboarding flow for this redesign.

## Selected Stop Sheet

When a stop is selected, the bottom sheet becomes a stop detail card.

Required content:

- Stop name and locality.
- Favourite toggle.
- Primary **Directions** button visible immediately.
- Compact refresh/status controls.
- Live departure board.

Departure row hierarchy:

- Line pill first.
- Destination second.
- Countdown/status trailing.
- Delay, cancellation, stale, and platform indicators only when meaningful.
- Track-departure action remains available but visually secondary to the departure time/countdown.

The selected stop sheet should feel like Apple Maps place details: direct actions at the top, details below, and no separate section picker.

## Search

Search moves from a bottom-sheet section to the top floating search pill.

Search behavior:

- Tapping the pill transitions to `search` and focuses the text field.
- Query results use local GTFS stop search.
- Empty query state shows nearby suggestions instead of a blank panel.
- Selecting a result centers the map and transitions to `stopDetail(stop)`.

Search should be one tap from anywhere in the primary map experience.

## Directions

Route planning starts from the selected stop sheet.

- A visible primary **Directions** button appears in the selected stop header/action area.
- In-app MapKit route calculation is used where feasible.
- Apple Maps handoff remains available as the reliable fallback.
- The route state should display route summary and errors without replacing the map background.

## Alerts

Alerts have two entry points:

1. A top-level alert badge/button near the search/top control area.
2. A compact inline row in the commute home sheet only when alerts are active or relevant.

The inline row should stay compact, for example: `1 disruption near your favourites`. It should not dominate the commute dashboard.

The full alerts list is a secondary contextual sheet state, not part of the default daily flow.

## Visual System

The selected visual personality is **Luxembourg transit subtle identity**:

- Apple Maps-like structure.
- Native system materials and blur.
- SF Symbols.
- Standard iOS typography.
- Subtle Luxembourg red/blue accents where useful.
- Transit line-color pills for scannability.
- Avoid heavy custom branding, oversized icons, or button clutter.

The result should feel native first and branded second.

## Technical Implementation Shape

### Existing Code to Evolve

Current relevant areas:

- `LuxTransit/LuxTransit/Features/Map/Views/TransitMapScreen.swift`
- `LuxTransit/LuxTransit/Features/Map/ViewModels/TransitMapViewModel.swift`
- `LuxTransit/LuxTransit/Features/BottomSheet/Views/TransitBottomSheet.swift`
- `LuxTransit/LuxTransit/Features/BottomSheet/Views/BottomSheetContent.swift`
- existing feature views for stops, search, routes, favourites, alerts, and settings

### Proposed Component Boundaries

- `TransitMapScreen`
  - owns the full map, floating controls, and high-level state wiring.
- `FloatingSearchBar`
  - renders the Apple Maps-style search pill and active search field affordance.
- `MapControlStack`
  - renders location, alert, and overflow/settings controls.
- `TransitBottomSheet`
  - becomes the reusable draggable shell only; it should not own a mode menu header.
- `CommuteDashboardView`
  - renders favourites-first home, empty state, nearby suggestions, and compact alert summary.
- `FavouriteStopDepartureCard`
  - renders collapsed/expanded favourite stop groups.
- `SelectedStopSheetView`
  - renders stop header, favourite, Directions, refresh/status, and departures.
- `DepartureRow`
  - reusable polished departure row used in commute and stop detail contexts.
- `AlertsSummaryRow`
  - compact alert affordance for the commute sheet.
- Existing `SearchView`, `RouteView`, `AlertsView`, and `SettingsView`
  - reused or refactored to fit the contextual shell.

### State and Data Flow

`TransitMapViewModel` should keep service coordination and map state, while gaining presentation state for:

- active sheet context
- selected stop
- expanded favourite stop IDs
- route state
- alert relevance summary

Networking and persistence should remain outside SwiftUI view bodies. Views should render passed data and invoke explicit actions.

### Loading, Empty, and Error States

Keep all existing honest states, but make them visually lighter:

- Prefer inline loading rows for commute and departure refresh.
- Use compact retry affordances where possible.
- Reserve `ContentUnavailableView` for full empty states.
- Keep stale labels contextual and small.
- Do not invent live data when unavailable.

## Accessibility Requirements

The redesign should preserve and improve baseline accessibility:

- Dynamic Type support for cards, rows, and controls.
- VoiceOver labels for map controls, stop markers, favourite toggles, Directions, alerts, and departure tracking.
- Sufficient contrast in light and dark mode.
- Tap targets should remain at least 44x44 points for primary controls.
- Sheet drag handle and state changes should remain understandable with accessibility labels.

## Validation Plan

Implementation should be validated with the Xcode build MCP as requested.

Suggested validation steps:

1. Build the main app scheme using the Xcode build MCP.
2. Run available targeted tests for existing parser/mapper behavior.
3. Render SwiftUI previews where feasible for redesigned components.
4. Run the app in a simulator to visually inspect:
   - launch home commute sheet
   - no-favourites get-started state
   - search flow
   - selected stop flow
   - Directions action
   - alerts access
   - light/dark mode basics

## Scope Boundaries

In scope:

- Complete primary UI shell overhaul.
- Contextual bottom sheet navigation.
- Commute dashboard.
- Search promotion to floating control.
- Selected stop redesign.
- Directions and alerts entry-point redesign.
- Visual polish toward Apple Maps-like native design.

Out of scope for this pass:

- New backend services.
- Full GTFS journey planning.
- Account systems or cloud sync.
- Widget redesign unless required by shared models.
- Live Activity redesign unless existing tracking UI must be adjusted for consistency.
