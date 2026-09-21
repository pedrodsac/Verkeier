import SwiftUI

/// View-layer extensions on ``TransportMode`` providing the canonical
/// SF Symbol and tint colour used across all route planner components.
///
/// Keep this file as the single source of truth for mode iconography;
/// do not duplicate these mappings inline in other views.
extension TransportMode {
    /// The SF Symbol name for this mode.
    var symbolName: String {
        switch self {
        case .train: "train.side.front.car"
        case .tram: "tram.fill"
        case .bus: "bus.fill"
        case .funicular: "cablecar.fill"
        case .bicycle: "bicycle"
        case .walking: "figure.walk"
        case .unknown: "mappin.circle.fill"
        }
    }

    /// The semantic accent colour for this mode.
    var tint: Color {
        switch self {
        case .train: .red
        case .tram: .orange
        case .bus: .blue
        case .funicular: .purple
        case .bicycle: .teal
        case .walking: .green
        case .unknown: .secondary
        }
    }
}

extension Collection<TransportMode> {
    /// The highest-priority mode for display, rail before road, so a stop served
    /// by several modes shows one representative icon. Unclassified stops stay
    /// visibly unknown rather than being presented as buses.
    ///
    /// Single source of truth for the icon a multi-mode stop should show;
    /// callers pick the tint separately (a favourite pin may stay yellow).
    var primaryMode: TransportMode {
        if contains(.train) { return .train }
        if contains(.tram) { return .tram }
        if contains(.funicular) { return .funicular }
        if contains(.bus) { return .bus }
        return .unknown
    }
}
