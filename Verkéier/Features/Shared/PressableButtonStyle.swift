import SwiftUI

/// A chrome-free button style that adds a subtle press-scale for tactile
/// feedback, replacing bare `.buttonStyle(.plain)` on tappable rows and cards.
///
/// Keeps `.plain`'s no-background look; only the press scale is added, and it is
/// suppressed under Reduce Motion. Use via `.buttonStyle(.pressable)`.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        // Read the accessibility environment from a nested View — a ButtonStyle
        // struct is not itself in the view tree, so @Environment must live here.
        PressableLabel(configuration: configuration)
    }

    private struct PressableLabel: View {
        let configuration: Configuration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
                .animation(
                    Animation.respectingReduceMotion(.snappy(duration: 0.25), reduceMotion),
                    value: configuration.isPressed
                )
        }
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    /// A chrome-free style with a subtle press-scale. See ``PressableButtonStyle``.
    static var pressable: PressableButtonStyle {
        PressableButtonStyle()
    }
}
