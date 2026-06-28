import CoreLocation
import SwiftUI

struct StopListRow: View {
    let stop: Stop
    var markerColor: Color = .blue
    var accessorySystemName: String? = "chevron.right"
    var referenceLocation: CLLocation?
    var routes: [TransitRoute] = []
    let action: () -> Void

    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(transitColor.gradient, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(stop.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let locality = stop.locality {
                            Text(locality)
                        } else {
                            Text(stop.dataSource.displayName)
                        }

                        Divider()
                            .frame(height: 10)

                        if let lineSummary {
                            Text(lineSummary)
                        } else if !stop.modes.isEmpty {
                            Text(modeSummary)
                        }

                        if let distanceMetadata {
                            Divider()
                                .frame(height: 10)

                            Text(distanceMetadata)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let accessorySystemName {
                    Image(systemName: accessorySystemName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.separator.opacity(0.35), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var iconName: String {
        if stop.modes.contains(.train) { return "train.side.front.car" }
        if stop.modes.contains(.tram) { return "tram.fill" }
        if stop.modes.contains(.funicular) { return "cablecar.fill" }
        return "bus.fill"
    }

    private var transitColor: Color {
        if stop.modes.contains(.train) { return .red }
        if stop.modes.contains(.tram) { return .orange }
        return markerColor
    }

    private var modeSummary: String {
        stop.modes.map(\.displayName).joined(separator: ", ")
    }

    /// Up to four route short names, e.g. "12 · 14 · 25", truncated with "…".
    private var lineSummary: String? {
        let names = routes.map(\.shortName).filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }
        let shown = names.prefix(4).joined(separator: " · ")
        return names.count > 4 ? "\(shown) …" : shown
    }

    private var accessibilityLabel: String {
        var parts: [String] = [stop.name]
        if let locality = stop.locality {
            parts.append(locality)
        }
        if let distanceMetadata {
            parts.append(distanceMetadata)
        }
        return parts.joined(separator: ", ")
    }

    private var distanceMetadata: String? {
        guard let referenceLocation else { return nil }

        let distance = CLLocation(
            latitude: stop.location.latitude,
            longitude: stop.location.longitude
        ).distance(from: referenceLocation)
        guard distance.isFinite else { return nil }

        return "\(preferences.formattedDistance(distance)) · \(walkingETA(for: distance))"
    }

    /// Walking time at ~5 km/h (83.3 m/min), rounded up. "<1 min" under 50 m.
    private func walkingETA(for meters: CLLocationDistance) -> String {
        if meters < 50 { return "<1 min" }
        let minutes = Int((meters / 83.3).rounded(.up))
        return "~\(minutes) min"
    }
}

#Preview {
    StopListRow(
        stop: Stop(
            id: "200209001",
            name: "Hamilius",
            locality: "Luxembourg",
            location: LocationPoint(latitude: 49.6107, longitude: 6.1268),
            modes: [.bus, .tram],
            dataSource: .mock
        ),
        action: {}
    )
    .padding(.horizontal, 16)
    .environment(AppPreferences())
}
