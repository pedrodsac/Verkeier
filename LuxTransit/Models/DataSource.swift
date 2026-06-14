import Foundation

enum DataSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case atpOpenAPI
    case gtfs
    case avl
    case mapKit
    case local
    case mock

    var id: String { rawValue }

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
