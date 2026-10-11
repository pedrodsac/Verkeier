import SwiftUI

struct DepartureTripDestination: View {
    let departure: Departure
    let stop: Stop
    let open: (TripDetailSelection) -> Void
    @Environment(\.tripDetailService) private var service
    @State private var model = DepartureTripViewModel()

    var body: some View {
        List {
            if let message = model.errorMessage {
                ContentUnavailableView("Run unavailable", systemImage: "bus", description: Text(message))
            } else {
                ProgressView("Loading stops…")
            }
        }
        .navigationTitle(departure.lineName)
        .toolbarTitleDisplayMode(.inline)
        .task(id: departure) {
            if let selection = await model.resolve(departure, stop: stop, service: service) { open(selection) }
        }
    }
}
