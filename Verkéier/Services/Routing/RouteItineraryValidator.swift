import Foundation
import MobiliteitKit

typealias RouteValidationContext = JourneyValidationContext
typealias RouteFeasibility = JourneyFeasibility
typealias RouteInfeasibility = JourneyInfeasibility

/// Maps legacy fixture/persisted presentation models into the package validator.
nonisolated enum RouteItineraryValidator {
    static func assess(_ option: RouteOption, context: RouteValidationContext) -> RouteFeasibility {
        for (index, leg) in option.plan.legs.enumerated() {
            guard let incomingID = leg.continuesInSeatFromTripID else { continue }
            guard index > 0, leg.transportKind == .transit,
                  option.plan.legs[index - 1].transportKind == .transit,
                  option.plan.legs[index - 1].tripId == incomingID,
                  option.plan.legs[index - 1].destination == leg.origin else { return .invalid(.invalidContinuation) }
        }
        return JourneyItineraryValidator.assess(option.plan.legs.flatMap { leg -> [JourneyTimingLeg] in
            let timing = JourneyTimingLeg(kind: leg.transportKind == .transit ? .transit : .walk,
                departure: leg.realtimeDepartureTime ?? leg.departureTime ?? leg.scheduledDepartureTime,
                arrival: leg.realtimeArrivalTime ?? leg.arrivalTime ?? leg.scheduledArrivalTime,
                originStopID: leg.originStopId, destinationStopID: leg.destinationStopId,
                requiredTransferSeconds: leg.requiredTransferSeconds,
                walkingEvidence: leg.walkingEvidence == .estimate ? .estimate : .routedPedestrian)
            return leg.continuesInSeatFromTripID == nil ? [timing] : [JourneyTimingLeg(kind: .continuation, departure: nil, arrival: nil), timing]
        }, context: context)
    }
}
