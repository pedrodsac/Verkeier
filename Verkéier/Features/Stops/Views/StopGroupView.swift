import SwiftUI

struct StopGroupView: View {
    let viewModel: StopGroupPresentationModel

    var body: some View {
		List(viewModel.stops) { stop in
			NavigationLink(value: TransitSheetRoute.stopDetail(stop)) {
				StopRow(
					stop: stop,
					routes: viewModel.routesByStopId[stop.id] ?? []
				)
			}
		}
		.listStyle(.plain)
    }
}

#Preview {
    StopGroupView(
        viewModel: StopGroupPresentationModel(
            stops: [
                Stop(
                    id: "stop-1",
                    name: "Hamilius-Centre (Tram)",
                    locality: "Luxembourg",
                    location: LocationPoint(latitude: 49.6107, longitude: 6.1268),
                    modes: [.tram],
                    dataSource: .mock
                ),
                Stop(
                    id: "stop-2",
                    name: "Hamilius-Centre (Bus)",
                    locality: "Luxembourg",
                    location: LocationPoint(latitude: 49.6107, longitude: 6.1268),
                    modes: [.bus],
                    dataSource: .mock
                ),
            ],
            bikeShareStations: [],
            referenceLocation: nil,
            routesByStopId: [:]
        ),
    )
    .padding(.horizontal, 16)
}

private struct BikeShareStationListRow: View {
    let station: BikeShareStation

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: TransportMode.bicycle.symbolName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(TransportMode.bicycle.tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(station.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(availabilitySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Radius.row)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("vel’OH! \(station.displayName), \(availabilitySummary)")
    }

    private var availabilitySummary: String {
        let bikes = station.bikesAvailable.map(String.init) ?? "unknown"
        let docks = station.docksAvailable.map(String.init) ?? "unknown"
        return "\(bikes) bikes · \(docks) free docks"
    }
}
