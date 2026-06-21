import Foundation

nonisolated struct LineDetailDirection: Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
}

nonisolated struct LineStopSequenceEntry: Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let platform: String?
    let location: LocationPoint
}

nonisolated struct LineTimetableEntry: Hashable, Identifiable, Sendable {
    let id: String
    let departureTime: Date
    let originName: String
    let destinationName: String
}

nonisolated struct LineDetail: Hashable, Sendable {
    let route: TransitRoute
    let directions: [LineDetailDirection]
    let selectedDirectionID: String
    let stopSequence: [LineStopSequenceEntry]
    let upcomingDepartures: [LineTimetableEntry]
    let serviceSummary: String
    let mapOverlay: RouteMapOverlay?
}
