import Observation

/// The persistent navigation state for each primary bottom-sheet tab.
///
/// Keeping paths separate prevents a map selection or a quick action in one tab
/// from silently replacing navigation in another tab.
@MainActor
@Observable
final class TransitSheetNavigationState {
    var selectedTab: TransitSheetTab = .home
    var homePath: [TransitSheetRoute] = []
    var planPath: [TransitSheetRoute] = []

    var activePath: [TransitSheetRoute] {
        switch selectedTab {
        case .home:
            homePath
        case .plan:
            planPath
        case .settings:
            []
        }
    }
}

enum TransitSheetTab: Hashable, CaseIterable {
    case home
    case plan
    case settings
}
