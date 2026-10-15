import SwiftUI

/// Resolves a tapped departure to its trip, then replaces itself with the trip detail.
struct DepartureTripScreen: View {
    @Environment(SheetRouter.self) private var router
    @Environment(\.tripDetailService) private var service

    let departure: Departure
    let stop: Stop

    @State private var model = DepartureTripModel()

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
            if let selection = await model.resolve(departure, stop: stop, service: service) {
                router.openTrip(selection, replacing: departure, at: stop)
            }
        }
    }
}
