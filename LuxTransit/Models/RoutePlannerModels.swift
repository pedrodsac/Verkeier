import Foundation

/// How the route planner orders the alternatives it returns.
nonisolated enum RoutePlannerSortOption: String, Codable, CaseIterable, Identifiable {
    case fastest
    case fewestTransfers
    case leastWalking

    var id: String {
        rawValue
    }

    /// Localized title for the picker.
    var title: String {
        switch self {
        case .fastest: "Fastest"
        case .fewestTransfers: "Fewest Transfers"
        case .leastWalking: "Least Walking"
        }
    }
}

/// A rider's preferred transport mode for route planning.
nonisolated enum RoutePlannerModePreference: String, Codable, CaseIterable, Identifiable {
    /// No mode preference.
    case any
    case bus
    case tram
    case train

    var id: String {
        rawValue
    }

    /// Localized title for the picker.
    var title: String {
        switch self {
        case .any: "Any"
        case .bus: "Bus"
        case .tram: "Tram"
        case .train: "Train"
        }
    }

    /// The matching ``TransportMode``, or `nil` for ``any``.
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

/// The set of user-configurable constraints applied to route planning.
nonisolated struct RoutePlannerFilters: Codable, Hashable {
    /// Ordering preference for the returned options.
    var sort: RoutePlannerSortOption = .fastest
    /// Preferred transport mode.
    var modePreference: RoutePlannerModePreference = .any
    /// When `true`, avoid options with tight transfers.
    var avoidTightTransfers = false
    /// When `true`, prefer step-free / accessible options.
    var preferAccessible = false
}

/// When the rider wants to travel: right now, departing at a chosen time, or
/// arriving by a chosen time. Drives the route search anchor.
nonisolated enum RoutePlanningTime: Hashable {
    case leaveNow
    case departAt(Date)
    case arriveBy(Date)

    /// The chosen instant, or `nil` for ``leaveNow``.
    var date: Date? {
        switch self {
        case .leaveNow: nil
        case let .departAt(date), let .arriveBy(date): date
        }
    }

    var isNow: Bool {
        if case .leaveNow = self { return true }
        return false
    }
}

/// Where a ``RoutePlace`` originated, used for grouping and analytics-free
/// presentation in the planner.
nonisolated enum RoutePlaceSource: String, Codable, Hashable {
    case currentLocation
    case selectedStop
    case favourite
    case nearby
    case recent
    case preset
    case search
}

/// An origin or destination the rider can pick in the route planner.
///
/// Unlike ``Stop``, a place can also be a free coordinate (e.g. the current
/// device location), so ``stopId`` is optional.
nonisolated struct RoutePlace: Codable, Hashable, Identifiable {
    /// Stable identifier; defaults to ``stopId`` then the location id.
    let id: String
    /// Primary label.
    let title: String
    /// Optional secondary label, e.g. locality.
    let subtitle: String?
    /// Geographic position.
    let location: LocationPoint
    /// Underlying stop identifier, when the place is a stop.
    let stopId: String?
    /// Modes available at the place, when known.
    let modes: [TransportMode]
    /// Where the place came from.
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
        self.title = title.stationDisplayName
        self.subtitle = subtitle
        self.location = location
        self.stopId = stopId
        self.modes = modes
        self.source = source
    }

    /// Creates a place from an existing ``Stop``.
    init(stop: Stop, source: RoutePlaceSource) {
        self.init(
            id: stop.id,
            title: stop.displayName,
            subtitle: stop.locality,
            location: stop.location,
            stopId: stop.id,
            modes: stop.modes,
            source: source
        )
    }

    /// Builds the synthetic "Current Location" place for a device coordinate.
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

/// A saved commute the rider can re-plan with one tap.
///
/// When ``origin`` is `nil` the planner uses the rider's current location as the
/// starting point.
nonisolated struct RouteCommutePreset: Codable, Hashable, Identifiable {
    /// Stable identifier; defaults to a fresh UUID.
    let id: String
    /// Rider-facing name, e.g. `"Home → Work"`.
    let title: String
    /// Fixed origin, or `nil` to start from the current location.
    let origin: RoutePlace?
    /// Destination of the commute.
    let destination: RoutePlace
    /// When the preset was created, used for ordering.
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
