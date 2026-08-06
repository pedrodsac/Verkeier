import SwiftUI

extension Animation {
    /// Returns `base`, or `nil` when Reduce Motion is enabled, so no view
    /// animates against the user's accessibility setting. Pass the view's
    /// `@Environment(\.accessibilityReduceMotion)` value.
    ///
    /// Centralizes the reduce-motion check that every animated view shares,
    /// for both `.animation(_:value:)` and `withAnimation(_:)` call sites.
    static func respectingReduceMotion(_ base: Animation, _ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : base
    }
}
