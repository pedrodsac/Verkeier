import SwiftUI

struct ChevronDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        ChevronDisclosureGroup(configuration: configuration)
    }

    private struct ChevronDisclosureGroup: View {
        let configuration: Configuration

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {

                Button {
                    withAnimation(
                        Animation.respectingReduceMotion(.snappy(duration: 0.22), reduceMotion)
                    ) {
                        configuration.$isExpanded.wrappedValue.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        configuration.label

                        Spacer(minLength: 0)

                        Image(
                            systemName: configuration.$isExpanded.wrappedValue
                                ? "chevron.down"
                                : "chevron.right"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(
                    configuration.$isExpanded.wrappedValue ? "Expanded" : "Collapsed"
                )

                if configuration.$isExpanded.wrappedValue {
                    configuration.content
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}
