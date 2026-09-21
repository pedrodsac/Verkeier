import SwiftUI

struct NearbyStopsView: View {
    let viewModel: NearbyStopsPresentationModel
    let selectStop: (Stop) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nearby stops")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            if viewModel.isLoading {
                ProgressView("Loading stops")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView(
                    "Stops unavailable",
                    systemImage: "wifi.exclamationmark",
                    description: Text(errorMessage)
                )
            } else if viewModel.stops.isEmpty {
                ContentUnavailableView(
                    "No nearby stops",
                    systemImage: "mappin.slash",
                    description: Text("Try again when your location is available.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 8) {
                        ForEach(viewModel.stops) { stop in
                            Button {
                                selectStop(stop)
                            } label: {
                                StopRow(
                                    stop: stop,
                                    routes: viewModel.routesByStopId[stop.id] ?? [],
                                    walkingEstimate: viewModel.walkingEstimatesByStopID[stop.id]
                                )
                                .padding(8)
                                .cardSurface(radius: Radius.row)
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 0), spacing: 8),
            GridItem(.flexible(minimum: 0), spacing: 8)
        ]
    }
}

#Preview {
    NearbyStopsView(
        viewModel: NearbyStopsPresentationModel(
            stops: [],
            isLoading: false,
            errorMessage: nil,
            referenceLocation: nil
        ),
        selectStop: { _ in }
    )
}
