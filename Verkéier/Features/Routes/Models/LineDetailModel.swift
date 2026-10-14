import Foundation
import Observation

/// The timetable and map overlay of one line, in one direction.
@MainActor @Observable
final class LineDetailModel {
    var selectedLineDetailRoute: TransitRoute?
    var selectedLineDetailDirectionID: String?
    var selectedLineDetail: LineDetail?
    var selectedLineDetailErrorMessage: String?

    /// Prepares `route` for display. Returns `false` when it is already shown.
    @discardableResult
    func prepareLineDetail(_ route: TransitRoute) -> Bool {
        guard selectedLineDetailRoute != route else { return false }
        selectedLineDetailRoute = route
        selectedLineDetailDirectionID = nil
        selectedLineDetail = nil
        selectedLineDetailErrorMessage = nil
        return true
    }

    func selectLineDetailDirection(_ directionID: String) {
        selectedLineDetailDirectionID = directionID
    }

    func clearLineDetail() {
        selectedLineDetailRoute = nil
        selectedLineDetailDirectionID = nil
        selectedLineDetail = nil
        selectedLineDetailErrorMessage = nil
    }

    func loadLineDetail(using gtfsService: any GTFSService, now: Date = .now) async {
        guard let route = selectedLineDetailRoute else {
            selectedLineDetail = nil
            selectedLineDetailErrorMessage = "Choose a line to view its timetable."
            return
        }

        selectedLineDetailErrorMessage = nil
        selectedLineDetail = await gtfsService.lineDetail(
            for: route,
            directionID: selectedLineDetailDirectionID,
            at: now
        )
        if selectedLineDetail == nil {
            selectedLineDetailErrorMessage = "No active timetable data is available for this line."
        }
    }
}
