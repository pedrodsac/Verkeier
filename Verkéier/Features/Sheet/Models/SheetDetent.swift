import SwiftUI

/// How far the main sheet is pulled up.
enum SheetDetent: CaseIterable {
    case medium
    case expanded

    static let mediumPresentationDetent = PresentationDetent.fraction(0.50)
    static let expandedPresentationDetent = PresentationDetent.large

    static let presentationDetents: Set<PresentationDetent> = [
        mediumPresentationDetent,
        expandedPresentationDetent,
    ]

    var accessibilityLabel: String {
        switch self {
        case .medium: "Medium"
        case .expanded: "Expanded"
        }
    }

    var presentationDetent: PresentationDetent {
        switch self {
        case .medium:
            return Self.mediumPresentationDetent
        case .expanded:
            return Self.expandedPresentationDetent
        }
    }

    init(presentationDetent: PresentationDetent) {
        if presentationDetent == Self.expandedPresentationDetent {
            self = .expanded
        } else {
            self = .medium
        }
    }
}
