import SwiftUI

/// The card at the top of the route timeline: the door-to-door time range, the
/// mode/line ribbon, and a meta line (duration · transfers · distance). Its
/// times are computed the same way as the timeline's first and last rows, so the
/// header and the steps below can never disagree.
struct RouteTimelineSummaryCard: View {
    let option: RouteOption

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(option.isVelohOnly ? (durationText ?? "Scheduled route") : timeRangeText)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                RouteOptionBadge(status: option.status(at: .now))
            }

            RouteRibbon(legs: option.plan.legs)

            Text(metaText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Radius.card)
        .accessibilityElement(children: .combine)
    }

    private var timeRangeText: String {
        switch (option.departureTime, option.arrivalTime) {
        case let (.some(dep), .some(arr)):
            "\(dep.formatted(date: .omitted, time: .shortened)) – \(arr.formatted(date: .omitted, time: .shortened))"
        case let (.some(dep), .none):
            dep.formatted(date: .omitted, time: .shortened)
        default:
            "Scheduled route"
        }
    }

    private var metaText: String {
        let transfers = switch option.transferCount {
        case 0: "Direct"
        case 1: "1 transfer"
        default: "\(option.transferCount) transfers"
        }
        let meters = option.plan.distanceMeters ?? 0
        let dist = meters >= 1000
            ? String(format: "%.1f km", meters / 1000)
            : "\(Int(meters)) m"
        let bikeNote = option.hasBikeAvailabilityWarning ? "Bike availability uncertain" : nil
        let duration = option.isVelohOnly ? nil : durationText
        return [duration, transfers, dist, bikeNote].compactMap(\.self).joined(separator: "  ·  ")
    }

    /// Duration from the journey's own endpoints so it always equals
    /// arrival − departure shown in the header; falls back to the plan's
    /// estimate only when endpoints are unknown.
    private var durationText: String? {
        if let dep = option.departureTime, let arr = option.arrivalTime {
            return "\(max(1, Int((arr.timeIntervalSince(dep) / 60).rounded()))) min"
        }
        guard let estimate = option.plan.expectedTravelTime else { return nil }
        return "\(max(1, Int((estimate / 60).rounded()))) min"
    }
}
