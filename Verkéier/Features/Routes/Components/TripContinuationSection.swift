import Foundation

nonisolated struct TripContinuationSection: Identifiable {
    let id: TripRunIdentity
    let stopName: String
    let lineName: String
    let headsign: String?
    let mode: TransportMode
    let rows: [TripStopRowModel]
}
