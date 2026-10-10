import Foundation

nonisolated struct TripStopOccurrenceIdentity: Hashable {
    let instance: TripRunIdentity
    let sequence: Int
}
