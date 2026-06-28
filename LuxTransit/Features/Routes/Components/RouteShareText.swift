import Foundation

extension RouteOption {
    /// A plain-text summary of this option, suitable for the share sheet.
    func shareText(originTitle: String, destinationTitle: String) -> String {
        func clock(_ date: Date?) -> String {
            date?.formatted(date: .omitted, time: .shortened) ?? "--:--"
        }

        var lines = ["\(originTitle) → \(destinationTitle)"]

        if let arrive = arrivalTime {
            let depart = firstTransitDepartureTime ?? plan.legs.first?.departureTime
            let minutes = plan.expectedTravelTime.map { "\(Int($0 / 60)) min" }
            let detail = [minutes, "\(transferCount) transfer\(transferCount == 1 ? "" : "s")"]
                .compactMap(\.self).joined(separator: ", ")
            lines.append("Depart \(clock(depart)), arrive \(clock(arrive)) (\(detail))")
        }

        for leg in plan.legs {
            if leg.transportKind == .transit {
                let line = leg.routeName ?? "Transit"
                let from = leg.origin.name ?? "?"
                let to = leg.destination.name ?? "?"
                lines.append("• \(line)  \(clock(leg.departureTime)) \(from) → \(clock(leg.arrivalTime)) \(to)")
            } else {
                let dist = leg.distanceMeters.map {
                    $0 >= 1000 ? String(format: "%.1f km", $0 / 1000) : "\(Int($0)) m"
                }
                lines.append("• Walk \(dist ?? "")".trimmingCharacters(in: .whitespaces))
            }
        }

        lines.append("Planned with LuxTransit")
        return lines.joined(separator: "\n")
    }
}
