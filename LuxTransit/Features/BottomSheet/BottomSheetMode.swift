import SwiftUI

enum TransitSheetContext: String, CaseIterable, Identifiable, Hashable {
    case home
    case search
    case stopDetail
    case directions
    case alerts
    case settings

    var id: String { rawValue }

    var accessibilityLabel: String {
        switch self {
        case .home: "Commute"
        case .search: "Search"
        case .stopDetail: "Selected stop"
        case .directions: "Directions"
        case .alerts: "Alerts"
        case .settings: "Settings"
        }
    }
}

enum BottomSheetDetent: CaseIterable {
    case collapsed
    case medium
    case expanded

    var accessibilityLabel: String {
        switch self {
        case .collapsed: "Collapsed"
        case .medium: "Medium"
        case .expanded: "Expanded"
        }
    }

    func detent(after direction: AccessibilityAdjustmentDirection) -> BottomSheetDetent {
        let detents = Self.allCases
        guard let currentIndex = detents.firstIndex(of: self) else { return self }

        switch direction {
        case .increment:
            return detents[min(currentIndex + 1, detents.endIndex - 1)]
        case .decrement:
            return detents[max(currentIndex - 1, detents.startIndex)]
        @unknown default:
            return self
        }
    }

    var toggledFromHandleTap: BottomSheetDetent {
        switch self {
        case .collapsed, .medium:
            return .expanded
        case .expanded:
            return .medium
        }
    }
}
