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

    /// Presentation only: retain the original name for matching and routing.
    /// Tram feeds prefix the station with its locality before the first comma.
    func stationDisplayName(hidingLocality: Bool) -> String {
        let cleaned = stationDisplayName
        guard hidingLocality, let comma = cleaned.firstIndex(of: ",") else { return cleaned }
        let station = cleaned[cleaned.index(after: comma)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return station.isEmpty ? cleaned : station
    }

    /// Presentation only, for line headsigns. Tram headsigns omit the locality
    /// and are entirely upper-case; other modes keep the locality (the part
    /// before the first comma) upper-cased.
    func headsignDisplayName(isTram: Bool) -> String {
        if isTram { return stationDisplayName(hidingLocality: true).uppercased() }
        let cleaned = stationDisplayName
        guard let comma = cleaned.firstIndex(of: ",") else { return cleaned }
        return cleaned[..<comma].uppercased() + cleaned[comma...]
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
