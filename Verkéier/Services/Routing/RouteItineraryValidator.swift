import Foundation
import MobiliteitKit

typealias RouteValidationContext = JourneyValidationContext
typealias RouteFeasibility = JourneyFeasibility
typealias RouteInfeasibility = JourneyInfeasibility

/// Maps legacy fixture/persisted presentation models into the package validator.
nonisolated enum RouteItineraryValidator {
    static func assess(_ option: RouteOption, context: RouteValidationContext) -> RouteFeasibility {
        JourneyItineraryValidator.assess(option.plan.legs.map { leg in
            JourneyTimingLeg(kind: leg.transportKind == .transit ? .transit : .walk,
                departure: leg.realtimeDepartureTime ?? leg.departureTime ?? leg.scheduledDepartureTime,
                arrival: leg.realtimeArrivalTime ?? leg.arrivalTime ?? leg.scheduledArrivalTime,
                originStopID: leg.originStopId, destinationStopID: leg.destinationStopId,
                requiredTransferSeconds: leg.requiredTransferSeconds,
                walkingEvidence: leg.walkingEvidence == .estimate ? .estimate : .routedPedestrian)
        }, context: context)
    }
}
