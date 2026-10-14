import Foundation
import MobiliteitKit

enum RouteEndpoint: Hashable {
    case origin
    case destination

    var searchTitle: String {
        switch self {
        case .origin:
            "Search Origin"
        case .destination:
            "Search Destination"
        }
    }

    var searchPrompt: String {
        switch self {
        case .origin:
            "Search origin"
        case .destination:
            "Search destination"
        }
    }
}
