import Foundation

/// The result of a ``RouteService`` calculation: a set of route alternatives
/// plus the currently selected one.
///
/// A calculation always holds at least one option; ``plan`` traps if asked for
/// a plan when none exist, so treat an empty `options` as an error upstream.
struct RouteCalculation {
    /// The available route alternatives.
    let options: [RouteOption]
    /// Identifier of the selected option; falls back to the first option.
    let selectedOptionID: String?

    /// The selected option, or the first one when no valid selection is set.
    var selectedOption: RouteOption? {
        guard !options.isEmpty else { return nil }
        if let selectedOptionID,
           let match = options.first(where: { $0.id == selectedOptionID }) {
            return match
        }
        return options.first
    }

    /// The selected option's plan. Traps if `options` is empty.
    var plan: RoutePlan {
        guard let selectedOption else {
            preconditionFailure("RouteCalculation requires at least one route option")
        }
        return selectedOption.plan
    }

    /// The selected option's map overlay, if any.
    var mapOverlay: RouteMapOverlay? {
        selectedOption?.mapOverlay
    }
}
