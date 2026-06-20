import SwiftUI

struct NearbyStopsView: View {
    let viewModel: NearbyStopsPresentationModel
    let selectStop: (Stop) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Closest stops from mobiliteit.lu")
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
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.stops) { stop in
                            StopListRow(
                                stop: stop,
                                markerColor: .blue,
                                referenceLocation: viewModel.referenceLocation
                            ) {
                                selectStop(stop)
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
