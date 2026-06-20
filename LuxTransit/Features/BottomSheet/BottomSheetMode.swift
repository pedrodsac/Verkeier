import SwiftUI

enum TransitSheetContext: String, CaseIterable, Identifiable, Hashable {
    case home
    case search
    case stopDetail
    case directions
    case routeTimeline
    case alerts
    case settings

    var id: String { rawValue }

    var accessibilityLabel: String {
        switch self {
        case .home: "Commute"
        case .search: "Search"
        case .stopDetail: "Selected stop"
        case .directions: "Directions"
        case .routeTimeline: "Selected route"
        case .alerts: "Alerts"
        case .settings: "Settings"
        }
    }
}

enum BottomSheetDetent: CaseIterable {
    case collapsed
    case medium
    case expanded

    static let collapsedPresentationDetent = PresentationDetent.height(70)
    static let mediumPresentationDetent = PresentationDetent.fraction(0.50)
    static let expandedPresentationDetent = PresentationDetent.large

    static let presentationDetents: Set<PresentationDetent> = [
        collapsedPresentationDetent,
        mediumPresentationDetent,
        expandedPresentationDetent,
    ]

    var accessibilityLabel: String {
        switch self {
        case .collapsed: "Collapsed"
        case .medium: "Medium"
        case .expanded: "Expanded"
        }
    }

    var presentationDetent: PresentationDetent {
        switch self {
        case .collapsed:
            return Self.collapsedPresentationDetent
        case .medium:
            return Self.mediumPresentationDetent
        case .expanded:
            return Self.expandedPresentationDetent
        }
    }

    init(presentationDetent: PresentationDetent) {
        if presentationDetent == Self.collapsedPresentationDetent {
            self = .collapsed
        } else if presentationDetent == Self.expandedPresentationDetent {
            self = .expanded
        } else {
            self = .medium
        }
    }
}
