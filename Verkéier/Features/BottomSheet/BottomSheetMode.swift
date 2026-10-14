import SwiftUI

enum TransitSheetRoute: Hashable {
    case search
    case stopGroup
    case stopDetail(Stop)
    case directionsForPreset(String)
    case routePlaceSearch(RouteEndpoint)
    case routeTimeline(String)
    case departureTrip(Departure, Stop)
    case tripDetail(TripDetailSelection)
    case lineDetail(TransitRoute)
    case alerts

    var defaultDetent: BottomSheetDetent {
        switch self {
        case .search, .routePlaceSearch, .routeTimeline, .lineDetail, .alerts:
            .expanded
        case .stopGroup, .stopDetail, .directionsForPreset, .tripDetail, .departureTrip:
            .medium
        }
    }

    var navigationTitle: String {
        switch self {
        case .search:
            "Search"
        case .stopGroup:
            "Stops at this location"
        case let .stopDetail(stop):
            stop.displayName
        case .directionsForPreset:
            "Directions"
        case let .routePlaceSearch(endpoint):
            endpoint.searchTitle
        case .routeTimeline:
            "Selected route"
        case let .departureTrip(departure, _):
            departure.lineName
        case let .tripDetail(selection):
            selection.lineName
        case let .lineDetail(route):
            route.shortName.isEmpty ? "Line details" : route.shortName
        case .alerts:
            "Service Alerts"
        }
    }
}

enum TransitSheetTab: Hashable, CaseIterable {
    case home
    case plan
    case settings
}

enum BottomSheetDetent: CaseIterable {
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
