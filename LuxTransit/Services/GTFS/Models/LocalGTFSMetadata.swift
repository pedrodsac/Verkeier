import Foundation

nonisolated struct LocalGTFSMetadata: Codable, Equatable, Sendable {
    let resourceId: String
    let title: String
    let checksum: String?
    let lastModified: Date?
    let downloadedAt: Date
    let indexedAt: Date?
}

nonisolated struct GTFSUpdateSnapshot: Equatable, Sendable {
    var metadata: LocalGTFSMetadata?
    var lastMetadataCheckAt: Date?
    var status: GTFSUpdateStatus

    static let empty = GTFSUpdateSnapshot(
        metadata: nil,
        lastMetadataCheckAt: nil,
        status: .idle
    )
}

nonisolated enum GTFSUpdateStatus: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case updated
    case failed
}

extension Notification.Name {
    static let gtfsDidUpdate = Notification.Name("gtfsDidUpdate")
}
