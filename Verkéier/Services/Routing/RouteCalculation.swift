import Foundation
import MobiliteitKit

/// The result of a ``RouteService`` calculation: a set of route alternatives
/// plus the currently selected one.
///
/// A successful calculation has at least one primary or supplemental option.
/// ``plan`` traps when both lists are empty; use `allOptions` when checking results.
nonisolated struct RouteCalculation: Sendable {
    /// The primary route profile, including accumulated adjacent pages and
    /// optionally the direct all-the-way walking comparison.
    var diagnostics: RoutingDiagnostics? = nil
    let options: [RouteOption]
    /// A best-effort bike-inclusive alternative that never consumes a transit slot.
    var supplementalOptions: [RouteOption] = []
    /// Scheduled option identifiers that realtime explicitly proved unusable.
    /// Presentation may retain any other scheduled option when live coverage is incomplete.
    var invalidatedOptionIDs: Set<String> = []
    /// More alternatives from this same calculation will be published shortly.
    var hasMoreOptions = false
    var isAuthoritativeSnapshot = false
    var canLoadEarlier: Bool? = nil
    var canLoadLater: Bool? = nil
    /// Compatibility fallback; each option carries its own page constraint.
    var validationContext: RouteValidationContext? = nil
    var browsingWindow: JourneyBrowsingWindow? = nil
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

    /// The selected option's plan. Traps if `allOptions` is empty.
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
