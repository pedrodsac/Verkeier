import Foundation

/// The rider-facing form of a transit station name.
///
/// These qualifiers describe the transport mode in the feed, but are already
/// conveyed by the station's mode and icon throughout the app.
nonisolated extension String {
    var stationDisplayName: String {
        [" (Tram)", " (Bus)", " (prov.)"]
            .reduce(self) { result, qualifier in
                result.replacingOccurrences(of: qualifier, with: "")
            }
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether two feed-provided names identify the same station.
    ///
    /// ATP directions can omit the locality prefix used by GTFS stop names,
    /// so compare both the canonical name and the portion after the first
    /// comma. This is used to suppress arrivals that ATP includes on a
    /// departure board when the selected stop is the trip's terminus.
    func identifiesSameStation(as other: String) -> Bool {
        let lhs = stationNameAliases
        let rhs = other.stationNameAliases
        return !lhs.isDisjoint(with: rhs)
    }

    private var stationNameAliases: Set<String> {
        let canonical = stationDisplayName
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !canonical.isEmpty else { return [] }

        var aliases: Set<String> = [canonical]
        if let comma = canonical.firstIndex(of: ",") {
            let localName = canonical[canonical.index(after: comma)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !localName.isEmpty { aliases.insert(localName) }
        }
        return aliases
    }
}
