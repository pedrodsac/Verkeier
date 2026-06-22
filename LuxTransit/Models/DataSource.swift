import Foundation

/// Provenance of a piece of transit data.
///
/// Carried on most domain models so the UI can attribute information and so the
/// app never presents mock or fallback data as if it were live production data.
enum DataSource: String, Codable, CaseIterable, Identifiable, Sendable {
    /// mobiliteit.lu OpenAPI departures / nearby stops.
    case atpOpenAPI
    /// The bundled or downloaded GTFS feed.
    case gtfs
    /// Ville de Luxembourg AVL disruption messages.
    case avl
    /// Apple Maps / MapKit routing.
    case mapKit
    /// On-device computed or cached data.
    case local
    /// Mock fixtures used in previews and tests.
    case mock

    var id: String { rawValue }

    /// Human-readable attribution label for the source.
    var displayName: String {
        switch self {
        case .atpOpenAPI: "mobiliteit.lu OpenAPI"
        case .gtfs: "GTFS"
        case .avl: "AVL"
        case .mapKit: "Apple Maps"
        case .local: "Local"
        case .mock: "Mock"
        }
    }
}
