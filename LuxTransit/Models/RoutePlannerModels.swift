import Foundation

nonisolated enum RoutePlannerSortOption: String, Codable, CaseIterable, Identifiable, Sendable {
    case fastest
    case fewestTransfers
    case leastWalking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fastest: "Fastest"
        case .fewestTransfers: "Fewest Transfers"
        case .leastWalking: "Least Walking"
        }
    }
}

nonisolated enum RoutePlannerModePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case any
    case bus
    case tram
    case train

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: "Any"
        case .bus: "Bus"
        case .tram: "Tram"
        case .train: "Train"
        }
    }

    var transportMode: TransportMode? {
        switch self {
        case .any:
            nil
        case .bus:
            .bus
        case .tram:
            .tram
        case .train:
            .train
        }
    }
}

nonisolated struct RoutePlannerFilters: Codable, Hashable, Sendable {
    var sort: RoutePlannerSortOption = .fastest
    var modePreference: RoutePlannerModePreference = .any
    var avoidTightTransfers = false
    var preferAccessible = false
}

nonisolated enum RoutePlaceSource: String, Codable, Hashable, Sendable {
    case currentLocation
    case selectedStop
    case favourite
    case nearby
    case recent
    case preset
    case search
}

nonisolated struct RoutePlace: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let location: LocationPoint
    let stopId: String?
    let modes: [TransportMode]
    let source: RoutePlaceSource

    init(
        id: String? = nil,
        title: String,
        subtitle: String? = nil,
        location: LocationPoint,
        stopId: String? = nil,
        modes: [TransportMode] = [],
        source: RoutePlaceSource
    ) {
        self.id = id ?? stopId ?? location.id
        self.title = title
        self.subtitle = subtitle
        self.location = location
        self.stopId = stopId
        self.modes = modes
        self.source = source
    }

    init(stop: Stop, source: RoutePlaceSource) {
        self.init(
            id: stop.id,
            title: stop.name,
            subtitle: stop.locality,
            location: stop.location,
            stopId: stop.id,
            modes: stop.modes,
            source: source
        )
    }

    static func currentLocation(_ location: LocationPoint) -> RoutePlace {
        RoutePlace(
            id: "current-location",
            title: "Current Location",
            subtitle: "Live device location",
            location: location,
            source: .currentLocation
        )
    }
}

nonisolated struct RouteCommutePreset: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let origin: RoutePlace?
    let destination: RoutePlace
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        origin: RoutePlace?,
        destination: RoutePlace,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.origin = origin
        self.destination = destination
        self.createdAt = createdAt
    }
}
