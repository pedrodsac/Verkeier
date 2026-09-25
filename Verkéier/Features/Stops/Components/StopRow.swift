import SwiftUI

/// The label used for stops in native lists and tappable cards.
/// Containers own navigation, selection, separators, and surface styling.
struct StopRow: View {
    let stop: Stop
    var markerColor: Color? = nil
    var title: String? = nil
    var subtitle: String? = nil
    var iconName: String? = nil
    var routes: [TransitRoute] = []
    var walkingEstimate: OfflineWalkingEstimate?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName ?? stop.modes.primaryMode.symbolName)
				.font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(transitColor.gradient, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title ?? stop.displayName)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(spacing: 6) {
                    Text(subtitle ?? detailText)

                    if servesNightBus {
                        Divider()
                            .frame(height: 10)

                        Image(systemName: "moon.stars.fill")
                            .foregroundStyle(.indigo)
                            .accessibilityLabel("Night bus")
                    }
                }
				.font(.caption)
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title ?? stop.displayName), \(subtitle ?? detailText)")
    }

    private var transitColor: Color {
        let mode = stop.modes.primaryMode
        return markerColor ?? (mode == .unknown ? .blue : mode.tint)
    }

    private var subtitleLocation: String {
        if let locality = stop.locality?.trimmingCharacters(in: .whitespacesAndNewlines),
           !locality.isEmpty {
            return locality
        }

        guard stop.name.contains("(") else {
            return commaSeparatedLocation ?? "Luxembourg"
        }

        let nameWithoutQualifier = stop.name
            .components(separatedBy: "(")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? stop.name

        guard let separator = nameWithoutQualifier.lastIndex(of: "-") else {
            return commaSeparatedLocation ?? "Luxembourg"
        }

        let inferredLocation = nameWithoutQualifier[nameWithoutQualifier.index(after: separator)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return inferredLocation.isEmpty
            ? (commaSeparatedLocation ?? "Luxembourg")
            : String(inferredLocation)
    }

    private var commaSeparatedLocation: String? {
        let firstComponent = stop.name
            .components(separatedBy: ",")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstComponent, !firstComponent.isEmpty,
              stop.name.contains(",") else { return nil }
        return firstComponent
    }

    private var detailText: String {
        guard let walkingEstimate else { return subtitleLocation }
        return "\(walkingEstimate.formattedDuration) walk · \(walkingEstimate.formattedDistance) · \(subtitleLocation)"
    }

    private var servesNightBus: Bool {
        routes.contains { $0.isNightService }
    }
}

#Preview {
    List {
        StopRow(
            stop: Stop(
                id: "200209001",
                name: "Hamilius",
                locality: "Luxembourg",
                location: LocationPoint(latitude: 49.6107, longitude: 6.1268),
                modes: [.bus, .tram],
                dataSource: .mock
            )
        )
    }
}
