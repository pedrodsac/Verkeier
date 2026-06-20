import Foundation

struct RouteCalculation {
    let options: [RouteOption]
    let selectedOptionID: String?

    var selectedOption: RouteOption? {
        guard !options.isEmpty else { return nil }
        if let selectedOptionID,
           let match = options.first(where: { $0.id == selectedOptionID }) {
            return match
        }
        return options.first
    }

    var plan: RoutePlan {
        guard let selectedOption else {
            preconditionFailure("RouteCalculation requires at least one route option")
        }
        return selectedOption.plan
    }

    var mapOverlay: RouteMapOverlay? {
        selectedOption?.mapOverlay
    }
}
