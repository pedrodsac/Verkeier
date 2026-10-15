import Foundation

extension Departure {
    var displayDestination: String {
        destination.stationDisplayName(hidingLocality: lineName.uppercased().hasPrefix("T"))
    }
}
