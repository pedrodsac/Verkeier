import SwiftUI

struct SpecialEventRow: View {
    let event: SpecialEvent
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            rowContent
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title), \(event.subtitle)")
        .accessibilityHint("Shows \(event.stopName)")
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            Image(systemName: event.symbolName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: event.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(verbatim: event.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .stroke(.separator.opacity(0.3), lineWidth: 0.5)
        }
    }

    private var accentColor: Color {
        switch event.accentColor {
        case .pink:
            .pink
        }
    }

    private var backgroundColor: Color {
        switch event.backgroundColor {
        case .pink:
            colorScheme == .dark
                ? Color(red: 0.26, green: 0.11, blue: 0.16)
                : Color(red: 1.0, green: 0.93, blue: 0.95)
        }
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    SpecialEventRow(event: SpecialEventCatalog.allEvents[0], action: {})
        .padding(16)
}
