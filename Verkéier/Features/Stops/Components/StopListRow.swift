import CoreLocation
import SwiftUI

enum StopListRowSurface {
    case standard
    case favourite
}

struct StopListRow: View {
    let stop: Stop
    var markerColor: Color = .blue
    var accessorySystemName: String? = "chevron.right"
    var referenceLocation: CLLocation?
    var routes: [TransitRoute] = []
    var surface: StopListRowSurface = .standard
    var accessoryAction: (() -> Void)?
    var accessoryAccessibilityLabel: String?
    var action: (() -> Void)? = nil
    var navigationValue: TransitSheetRoute? = nil
	
    @Environment(\.colorScheme) private var colorScheme
	
    @ViewBuilder
    var body: some View {
        if let accessoryAction {
            surface {
                HStack(spacing: 0) {
                    Button(action: action ?? {}) {
                        rowContent(showsAccessory: false)
                    }
                    .buttonStyle(.pressable)

                    Button(action: accessoryAction) {
                        accessoryContent
                            .frame(width: 44, height: 62)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessoryAccessibilityLabel ?? "More options")
                }
            }
            .accessibilityElement(children: .contain)
        } else {
            surface {
                if let navigationValue {
                    NavigationLink(value: navigationValue) {
                        rowContent(showsAccessory: true)
                    }
                    .buttonStyle(.pressable)
                } else {
                    Button(action: action ?? {}) {
                        rowContent(showsAccessory: true)
                    }
                    .buttonStyle(.pressable)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
        }
    }

    @ViewBuilder
    private func surface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background {
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                    .fill(surfaceBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                    .stroke(surfaceBorder, lineWidth: 0.5)
            }
    }

    @ViewBuilder
    private func rowContent(showsAccessory: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: stop.modes.primaryMode.symbolName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(transitColor.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(stop.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(spacing: 6) {
                    Text(subtitleLocation)

                    if servesNightBus {
						Divider()
							.frame(height: 10)

                        Image(systemName: "moon.stars.fill")
                            .foregroundStyle(.indigo)
                            .accessibilityLabel("Night bus")
                    }

//                    if let lineSummary {
//                        Text(lineSummary)
//                    } else if !stop.modes.isEmpty {
//                        Text(modeSummary)
//                    }

                }
                .font(.caption)
                .foregroundStyle(.secondary)
				.minimumScaleFactor(0.7)
                .lineLimit(1)
            }

			if showsAccessory {
                Spacer(minLength: 8)

                accessoryContent
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var accessoryContent: some View {
        Group {
            if let accessorySystemName {
                Image(systemName: accessorySystemName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var surfaceBackground: AnyShapeStyle {
        switch surface {
        case .standard:
            AnyShapeStyle(.thinMaterial)
        case .favourite:
            AnyShapeStyle(favouriteColor.opacity(0.32))
        }
    }

    private var surfaceBorder: AnyShapeStyle {
		AnyShapeStyle(.separator.opacity(0.3))
    }

    private var favouriteColor: Color {
        colorScheme == .dark
            ? Color(red: 0.38, green: 0.28, blue: 0.08)
            : Color(red: 1.0, green: 0.91, blue: 0.58)
    }

    private var transitColor: Color {
        if stop.modes.contains(.train) { return .red }
        if stop.modes.contains(.tram) { return .orange }
        return markerColor
    }

    private var modeSummary: String {
        stop.modes.map(\.displayName).joined(separator: ", ")
    }

    /// ATP sometimes encodes the district in names such as
    /// "Hamilius-Centre (Tram)" instead of returning a separate locality.
    /// Keep the fallback in the shared row so nearby, search, favourite, and
    /// grouped-stop rows all render the same subtitle.
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

    /// True when any line serving this stop is a night service.
    private var servesNightBus: Bool {
        routes.contains { $0.isNightService }
    }

    /// Up to four route short names, e.g. "12 · 14 · 25", truncated with "…".
    private var lineSummary: String? {
        let names = routes.map(\.shortName).filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }
        let shown = names.prefix(4).joined(separator: " · ")
        return names.count > 4 ? "\(shown) …" : shown
    }

    private var accessibilityLabel: String {
        var parts: [String] = [stop.displayName]
        parts.append(subtitleLocation)
        return parts.joined(separator: ", ")
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
