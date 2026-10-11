import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Scoped to one card so unrelated drags cannot change a journey.
nonisolated struct RouteEndpointDragPayload: Codable, Transferable {
    let sessionID: UUID
    let isOrigin: Bool

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .routeEndpoint)
    }
}

private extension UTType {
    nonisolated static let routeEndpoint = UTType(exportedAs: "lu.verkeier.route-endpoint")
}
