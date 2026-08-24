import SwiftUI

enum TransitSheetRoute: Hashable {
    case search
    case stopGroup
    case stopDetail(Stop)
    case directions
    case directionsForPreset(String)
    case routePlaceSearch(RouteEndpoint)
    case routeTimeline(String)
    case lineDetail(TransitRoute)
    case alerts

    var defaultDetent: BottomSheetDetent {
        switch self {
        case .search, .routePlaceSearch, .routeTimeline, .lineDetail, .alerts:
            .expanded
        case .stopGroup, .stopDetail, .directions, .directionsForPreset:
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
        case .directions, .directionsForPreset:
            "Directions"
        case let .routePlaceSearch(endpoint):
            endpoint.searchTitle
        case .routeTimeline:
            "Selected route"
        case let .lineDetail(route):
            route.shortName.isEmpty ? "Line details" : route.shortName
        case .alerts:
            "Service Alerts"
        }
    }
}

@MainActor
struct TransitSheetRouteActivationCoordinator {
    let selectStop: (Stop, Bool) -> Void
    let loadSelectedStopData: () -> Void
    let calculateRoute: () -> Void
    let applyCommutePreset: (String) -> Void
    let selectRouteOption: (String) -> Void
    let prepareLineDetail: (TransitRoute) -> Bool
    let loadLineDetail: () -> Void

    func activate(
        _ route: TransitSheetRoute?,
        previousRoute: TransitSheetRoute?,
        isBackNavigation: Bool = false
    ) {
        guard let route else {
            return
        }

        guard !isBackNavigation else { return }

        switch route {
        case .search, .stopGroup, .routePlaceSearch, .alerts:
            break

        case let .stopDetail(stop):
            let preservesLineDetail: Bool
            if case .lineDetail = previousRoute {
                preservesLineDetail = true
            } else {
                preservesLineDetail = false
            }
            selectStop(stop, preservesLineDetail)
            loadSelectedStopData()

        case .directions:
            calculateRoute()

        case let .directionsForPreset(presetID):
            applyCommutePreset(presetID)
            calculateRoute()

        case let .routeTimeline(optionID):
            selectRouteOption(optionID)

        case let .lineDetail(route):
            if prepareLineDetail(route) {
                loadLineDetail()
            }
        }
    }
}

enum BottomSheetDetent: CaseIterable {
    case collapsed
    case medium
    case expanded

	static let collapsedPresentationDetent = PresentationDetent.height(87.5)
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
