import SwiftUI

/// A floating filter pill over the map that toggles which stop layers are
/// visible by mode: All · Bus · Tram · Train. Fully stateless — the selection
/// and setter come from ``TransitMapViewModel`` via the sheet actions.
struct MapModeFilterBar: View {
    let selected: TransportMode?
    let select: (TransportMode?) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let modes: [TransportMode?] = [nil, .bus, .tram, .train]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Self.modes, id: \.self) { mode in
                Button {
                    select(mode)
                } label: {
                    Text(label(for: mode))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(mode == selected ? Color.white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background {
                            if mode == selected {
                                Capsule().fill(.tint)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(label(for: mode))
                .accessibilityAddTraits(mode == selected ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(.separator.opacity(0.3), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .animation(Animation.respectingReduceMotion(.snappy(duration: 0.25), reduceMotion), value: selected)
    }

    private func label(for mode: TransportMode?) -> String {
        mode?.displayName ?? "All"
    }
}

#Preview {
    MapModeFilterBar(selected: .tram, select: { _ in })
        .padding()
}
