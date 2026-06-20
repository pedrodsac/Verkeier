import CoreLocation
import SwiftUI

struct StopListRow: View {
    let stop: Stop
    var markerColor: Color = .blue
    var accessorySystemName: String? = "chevron.right"
    var referenceLocation: CLLocation? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(transitColor.gradient, in: Circle())
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

                        if !stop.modes.isEmpty {
                            Text(modeSummary)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                    if let distanceMetadata {
                        Text(distanceMetadata)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
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

        let distanceText = formattedDistance(distance)
        let walkingText = formattedWalkingMinutes(for: distance)
        return "\(distanceText) · \(walkingText) walk"
    }

    private func formattedDistance(_ distance: CLLocationDistance) -> String {
        if distance < 1_000 {
            return "\(Int(distance.rounded())) m"
        }
        return String(format: "%.1f km", distance / 1_000)
    }

    private func formattedWalkingMinutes(for distance: CLLocationDistance) -> String {
        let minutes = max(1, Int((distance / 1.33 / 60).rounded()))
        return "\(minutes) min"
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
}
