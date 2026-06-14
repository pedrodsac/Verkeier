import SwiftUI

struct NearbyStopsView: View {
    let stops: [Stop]
    let isLoading: Bool
    let errorMessage: String?
    let selectStop: (Stop) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Closest stops from mobiliteit.lu")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            if isLoading {
                ProgressView("Loading stops")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Stops unavailable",
                    systemImage: "wifi.exclamationmark",
                    description: Text(errorMessage)
                )
            } else if stops.isEmpty {
                ContentUnavailableView(
                    "No nearby stops",
                    systemImage: "mappin.slash",
                    description: Text("Try again when your location is available.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(stops) { stop in
                            StopListRow(stop: stop, markerColor: .blue) {
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
        stops: [],
        isLoading: false,
        errorMessage: nil,
        selectStop: { _ in }
    )
}
