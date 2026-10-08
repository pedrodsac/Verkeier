import Foundation
import MobiliteitKit

/// Applies route comparisons to presentation without discarding the
/// underlying results needed by paging and subsequent timing refinements.
nonisolated enum RouteOptionVisibility {
    /// Publish every useful choice; paging state is maintained independently.
    static func presentedOptions(
        primary: [RouteOption], supplemental: [RouteOption], at now: Date
    ) -> (primary: [RouteOption], supplemental: [RouteOption]) {
        visibleOptions(primary: primary, supplemental: supplemental, at: now)
    }

    static func visibleOptions(
        primary: [RouteOption], supplemental: [RouteOption], at now: Date
    ) -> (primary: [RouteOption], supplemental: [RouteOption]) {
        let all = primary + supplemental
        let candidates = all.filter { $0.status(at: now).isSelectable }
        let dominatedIDs = Set(all.filter { option in
            candidates.contains { other in
                // Bike share is a separate mode choice, even when transit is faster.
                guard other.usesBikeShare == option.usesBikeShare,
                      other.id != option.id,
                      let departure = option.departureTime, let arrival = option.arrivalTime,
                      let otherDeparture = other.departureTime, let otherArrival = other.arrivalTime
                else { return false }
                guard !other.hasTightTransfer || option.hasTightTransfer else { return false }
                return otherDeparture >= departure && otherArrival <= arrival
                    && (otherDeparture > departure || otherArrival < arrival)
            }
        }.map(\.id))
        return walkingVisibleOptions(
            primary: primary.filter { !dominatedIDs.contains($0.id) },
            supplemental: supplemental.filter { !dominatedIDs.contains($0.id) },
            at: now
        )
    }

    private static func walkingVisibleOptions(
        primary: [RouteOption], supplemental: [RouteOption], at now: Date
    ) -> (primary: [RouteOption], supplemental: [RouteOption]) {
        let all = primary + supplemental
        let transit = all.filter { !$0.transitLegs.isEmpty && $0.status(at: now).isSelectable }
        guard !transit.isEmpty else { return (primary, supplemental) }

        let eligibleWalking = all.filter { walk in
            guard walk.isWalkingOnly, walk.status(at: now).isSelectable,
                  let arrival = walk.arrivalTime else { return false }
            return transit.allSatisfy { ride in
                guard let transitArrival = ride.arrivalTime else { return false }
                return arrival < transitArrival
            }
        }
        if let fastestWalk = eligibleWalking.min(by: { (duration($0) ?? .infinity) < (duration($1) ?? .infinity) }),
           let walkingDuration = duration(fastestWalk),
           transit.allSatisfy({ ride in
               guard let transitDuration = duration(ride) else { return false }
               return walkingDuration < transitDuration
           }) {
            return ([fastestWalk], supplemental.filter { !$0.isWalkingOnly })
        }

        let walkingIDs = Set(eligibleWalking.map(\.id))
        return (
            primary.filter { !$0.isWalkingOnly || walkingIDs.contains($0.id) },
            supplemental.filter { !$0.isWalkingOnly || walkingIDs.contains($0.id) }
        )
    }

    private static func duration(_ option: RouteOption) -> TimeInterval? {
        if let departure = option.departureTime, let arrival = option.arrivalTime {
            return arrival.timeIntervalSince(departure)
        }
        return option.plan.expectedTravelTime
    }
}
