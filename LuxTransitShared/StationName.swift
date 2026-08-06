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
}
