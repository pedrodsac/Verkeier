import SwiftUI

/// Corner radii shared across Verkéier surfaces, so rows, cards, and panels
/// stop drifting between 8/10/12/14/16/18 point literals.
///
/// Concentric rule: a nested element's radius = its container's radius − its
/// inset. e.g. a badge inset 4pt inside a `.card` (16) surface uses radius 12.
enum Radius {
    /// List rows and compact chips.
    static let row: CGFloat = 12
    /// Standard content cards (route options, alerts, departures).
    static let card: CGFloat = 16
    /// Prominent hero surfaces (the next-departure card).
    static let hero: CGFloat = 20
    /// The bottom sheet itself.
    static let sheet: CGFloat = 28
}

extension View {
    /// The canonical Verkéier surface: a continuous rounded rectangle filled
    /// with thin material and outlined by a hairline separator.
    ///
    /// Replaces the hand-rolled `background(.thinMaterial, in:) + overlay(stroke)`
    /// pattern that was duplicated across rows, cards, and panels.
    func cardSurface(radius: CGFloat = Radius.card) -> some View {
        background(.thinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(.separator.opacity(0.3), lineWidth: 0.5)
            }
    }
}
