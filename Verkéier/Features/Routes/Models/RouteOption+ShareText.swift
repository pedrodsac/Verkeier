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
            let minutes = plan.expectedTravelTime.map { duration in
                let value = isWalkingOnly ? (DurationDisplay.minutes(duration, rounding: .up) ?? 0) : Int(duration / 60)
                return "\(value) min"
            }
            let detail = [minutes, "\(transferCount) transfer\(transferCount == 1 ? "" : "s")"]
                .compactMap(\.self).joined(separator: ", ")
            lines.append("Depart \(clock(depart)), arrive \(clock(arrive)) (\(detail))")
        }

        for leg in plan.legs {
            if leg.transportKind == .transit {
                if leg.continuesInSeatFromTripID != nil {
                    lines.append(
                        "• Stay aboard at \(leg.origin.name?.stationDisplayName(hidingLocality: leg.mode == .tram) ?? "stop")"
                    )
                }
                let line = leg.routeName ?? "Transit"
                let from = leg.origin.name?.stationDisplayName(hidingLocality: leg.mode == .tram) ?? "?"
                let to = leg.destination.name?.stationDisplayName(hidingLocality: leg.mode == .tram) ?? "?"
                lines.append("• \(line)  \(clock(leg.departureTime)) \(from) → \(clock(leg.arrivalTime)) \(to)")
            } else if leg.transportKind == .bikeShare {
                let from =
                    leg.bikeShareDetails?.pickupStation.displayName
                    ?? leg.origin.name?.stationDisplayName(hidingLocality: leg.mode == .tram) ?? "station"
                let to =
                    leg.bikeShareDetails?.returnStation.displayName
                    ?? leg.destination.name?.stationDisplayName(hidingLocality: leg.mode == .tram) ?? "station"
                let bikes =
                    leg.bikeShareDetails?.pickupStation.bikesAvailable.map { "\($0) bikes" } ?? "availability unknown"
                let docks =
                    leg.bikeShareDetails?.returnStation.docksAvailable.map { "\($0) free docks" }
                    ?? "availability unknown"
                lines.append(
                    "• vel’OH! bike \(clock(leg.departureTime)) \(from) → \(clock(leg.arrivalTime)) \(to) (\(bikes), \(docks))"
                )
            } else {
                let dist = leg.distanceMeters.map {
                    $0 >= 1000 ? String(format: "%.1f km", $0 / 1000) : "\(Int($0)) m"
                }
                lines.append("• Walk \(dist ?? "")".trimmingCharacters(in: .whitespaces))
            }
        }

        if usesBikeShare {
            lines.append("Bike station data: JCDecaux vel’OH!")
        }
        lines.append("Planned with Verkéier")
        return lines.joined(separator: "\n")
    }
}
