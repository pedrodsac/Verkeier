import Foundation
import Observation

@MainActor @Observable
final class DepartureTripViewModel {
    var errorMessage: String?

    func resolve(_ departure: Departure, stop: Stop, service: any TripDetailService) async -> TripDetailSelection? {
        errorMessage = nil
        do {
            var selection = try await service.selection(for: departure, at: stop)
            try Task.checkCancellation()
            selection.highlightsRide = false
            return selection
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
