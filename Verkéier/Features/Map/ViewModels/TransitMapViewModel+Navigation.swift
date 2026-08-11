import CoreLocation
import MapKit
import Observation
import SwiftUI

extension TransitMapViewModel {
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
}
