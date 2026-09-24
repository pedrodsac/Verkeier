import Foundation

/// The original request instant is retained through asynchronous geometry work.
nonisolated struct RouteValidationContext: Hashable, Sendable {
    let anchor: Date
    let arriveBy: Bool
    let minimumTransferSeconds: Int
}

nonisolated enum RouteInfeasibility: String, Codable, Hashable, Sendable {
    case missingTime, negativeDuration, overlappingLegs
    case departureBeforeAnchor, missedTransfer, unverifiedTransferWalk, arrivalAfterDeadline
}

nonisolated enum RouteFeasibility: Codable, Hashable, Sendable {
    case feasible(minimumTransferSlack: TimeInterval?)
    case invalid(RouteInfeasibility)

    var isInvalid: Bool {
        if case .invalid = self { return true }
        return false
    }
}

/// Validates effective times after every duration-changing walking update.
nonisolated enum RouteItineraryValidator {
    static func assess(_ option: RouteOption, context: RouteValidationContext) -> RouteFeasibility {
        let legs = option.plan.legs
        guard let first = legs.first, let last = legs.last,
              let departure = effectiveDeparture(first),
              let arrival = effectiveArrival(last) else { return .invalid(.missingTime) }
        if !context.arriveBy && departure < context.anchor { return .invalid(.departureBeforeAnchor) }
        if context.arriveBy && arrival > context.anchor { return .invalid(.arrivalAfterDeadline) }

        for (index, leg) in legs.enumerated() {
            guard let start = effectiveDeparture(leg), let end = effectiveArrival(leg) else {
                return .invalid(.missingTime)
            }
            if end < start { return .invalid(.negativeDuration) }
            if index > 0, let previousEnd = effectiveArrival(legs[index - 1]),
               start < previousEnd { return .invalid(.overlappingLegs) }
        }

        let rides = legs.enumerated().filter { $0.element.transportKind == .transit }
        var minimumSlack: TimeInterval?
        for (incoming, outgoing) in zip(rides, rides.dropFirst()) {
            guard let incomingArrival = effectiveArrival(incoming.element),
                  let outgoingDeparture = effectiveDeparture(outgoing.element) else {
                return .invalid(.missingTime)
            }
            let transferWalks = legs[(incoming.offset + 1)..<outgoing.offset]
                .filter { $0.transportKind == .walking }
            if transferWalks.contains(where: { $0.walkingEvidence == .estimate }) {
                return .invalid(.unverifiedTransferWalk)
            }
            let movement = transferWalks
                .reduce(0.0) { total, walk in
                    total + max(0, (effectiveArrival(walk) ?? .distantPast)
                        .timeIntervalSince(effectiveDeparture(walk) ?? .distantPast))
                }
            let required = TimeInterval(outgoing.element.requiredTransferSeconds
                ?? context.minimumTransferSeconds)
            let slack = outgoingDeparture.timeIntervalSince(incomingArrival) - movement - required
            if slack < 0 { return .invalid(.missedTransfer) }
            minimumSlack = min(minimumSlack ?? slack, slack)
        }
        return .feasible(minimumTransferSlack: minimumSlack)
    }

    private static func effectiveDeparture(_ leg: RoutePlan.Leg) -> Date? {
        leg.realtimeDepartureTime ?? leg.departureTime ?? leg.scheduledDepartureTime
    }

    private static func effectiveArrival(_ leg: RoutePlan.Leg) -> Date? {
        leg.realtimeArrivalTime ?? leg.arrivalTime ?? leg.scheduledArrivalTime
    }
}
