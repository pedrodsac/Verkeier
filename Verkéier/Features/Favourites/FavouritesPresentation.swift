import Foundation

enum FavouriteDepartureBoardPhase: Equatable {
    case idle
    case loading
    case loaded
    case failed
}

struct FavouriteDepartureBoardSnapshot {
    var phase: FavouriteDepartureBoardPhase = .idle
    var departures: [Departure] = []
    var lastUpdated: Date?
    var errorMessage: String?

    func isStale(now: Date = .now) -> Bool {
        guard let lastUpdated else { return false }
        return now.timeIntervalSince(lastUpdated) > 90
    }

    var hasPreviousContent: Bool {
        !departures.isEmpty || lastUpdated != nil
    }
}

struct FavouriteStopPresentationModel: Identifiable {
    let stop: Stop
    let labels: [String]
    let departures: FavouriteDepartureBoardSnapshot

    var id: String { stop.id }
}

struct FavouritesPresentationModel {
    let stops: [FavouriteStopPresentationModel]
    let isRefreshing: Bool
    let liveDeparturesAvailable: Bool

    var availableLabels: [String] {
        let labels = stops.flatMap(\.labels)
        var seen = Set<String>()
        return labels.filter {
            seen.insert($0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)).inserted
        }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func labelSections(for stops: [FavouriteStopPresentationModel]? = nil) -> [FavouriteLabelSection] {
        var groups: [String: [FavouriteStopPresentationModel]] = [:]
        for favourite in stops ?? self.stops {
            let labels = favourite.labels.isEmpty ? [String(localized: "Saved Stops")] : favourite.labels
            for label in labels {
                groups[label, default: []].append(favourite)
            }
        }
        return groups
            .map { FavouriteLabelSection(title: $0.key, stops: $0.value) }
            .sorted {
                if $0.title == String(localized: "Saved Stops") { return false }
                if $1.title == String(localized: "Saved Stops") { return true }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }
}

struct FavouriteLabelSection: Identifiable {
    let title: String
    let stops: [FavouriteStopPresentationModel]

    var id: String { title }
}

struct FavouritesActions {
    var openStop: (Stop) -> Void = { _ in }
    var planTo: (Stop) -> Void = { _ in }
    var planFrom: (Stop) -> Void = { _ in }
    var refreshStop: (Stop) async -> Void = { _ in }
    var refreshAll: () async -> Void = {}
    var updateLabels: (String, [String]) -> Void = { _, _ in }
    var removeFavourite: (String) -> Void = { _ in }
    var findStop: () -> Void = {}
}
