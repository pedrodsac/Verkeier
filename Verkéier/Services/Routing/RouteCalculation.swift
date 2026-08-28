import Foundation

/// The result of a ``RouteService`` calculation: a set of route alternatives
/// plus the currently selected one.
///
/// A calculation always holds at least one option; ``plan`` traps if asked for
/// a plan when none exist, so treat an empty `options` as an error upstream.
struct RouteCalculation: Sendable {
    /// The primary public-transport departure profile (at most five journeys).
    let options: [RouteOption]
    /// A best-effort bike-inclusive alternative that never consumes a transit slot.
    var supplementalOptions: [RouteOption] = []
    /// Scheduled option identifiers that realtime explicitly proved unusable.
    /// Presentation may retain any other scheduled option when live coverage is incomplete.
    var invalidatedOptionIDs: Set<String> = []
    /// Identifier of the selected option; falls back to the first option.
    let selectedOptionID: String?

    var allOptions: [RouteOption] {
        options + supplementalOptions
    }

    /// The selected option, or the first one when no valid selection is set.
    var selectedOption: RouteOption? {
        guard !allOptions.isEmpty else { return nil }
        if let selectedOptionID,
           let match = allOptions.first(where: { $0.id == selectedOptionID }) {
            return match
        }
        return allOptions.first
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
