import SwiftUI

struct FavouriteCustomizationDraft: Identifiable {
    let stop: Stop
    var label: String
    var colorHex: String
    var iconName: String

    var id: String { stop.id }

    init(
        stop: Stop,
        label: String? = nil,
        colorHex: String? = nil,
        iconName: String? = nil
    ) {
        self.stop = stop
        self.label = label ?? stop.displayName
        self.colorHex = colorHex ?? "#007AFF"
        self.iconName = iconName ?? "house.fill"
    }
}

struct FavouriteCustomizerView: View {
    let stop: Stop
    let save: (String, String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var colorHex: String
    @State private var iconName: String

    private let colors = [
        "#FF453A", "#FF9F0A", "#FFD60A", "#30D158", "#64D2FF", "#007AFF",
        "#5E5CE6", "#FF375F", "#BF5AF2", "#AC8E68", "#8E8E93", "#F2B8B5"
    ]

    private let icons = [
        "house.fill", "building.2.fill", "figure.run", "graduationcap.fill", "cross.case.fill",
        "fork.knife", "cart.fill", "bag.fill", "person.fill", "heart.fill", "pawprint.fill",
        "airplane", "tram.fill", "bus.fill", "bicycle", "cup.and.saucer.fill",
        "dumbbell.fill", "book.fill", "leaf.fill", "tent.fill", "fuelpump.fill",
        "building.columns.fill", "briefcase.fill", "star.fill"
    ]

    init(
        stop: Stop,
        initialLabel: String? = nil,
        initialColorHex: String? = nil,
        initialIconName: String? = nil,
        save: @escaping (String, String, String) -> Void
    ) {
        self.stop = stop
        self.save = save
        let draft = FavouriteCustomizationDraft(
            stop: stop,
            label: initialLabel,
            colorHex: initialColorHex,
            iconName: initialIconName
        )
        _label = State(initialValue: draft.label)
        _colorHex = State(initialValue: draft.colorHex)
        _iconName = State(initialValue: draft.iconName)
    }

    var body: some View {
        NavigationStack {
            List {
				preview
				colorPicker
				iconPicker
            }
            .navigationTitle("New Favourite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
					Button("Done", systemImage: "checkmark") {
                        let cleanedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !cleanedLabel.isEmpty else { return }
                        save(cleanedLabel, colorHex, iconName)
                        dismiss()
                    }
                    .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
					.labelStyle(.iconOnly)
                    .accessibilityLabel("Save favourite")
                }
            }
        }
    }

    private var preview: some View {
		Section {
			VStack(spacing: 18) {
				Image(systemName: iconName)
					.font(.system(size: 48, weight: .medium))
					.foregroundStyle(.white)
					.frame(width: 118, height: 118)
					.background(Color(hex: colorHex), in: Circle())
					.accessibilityHidden(true)
				
				TextField("Favourite Name", text: $label)
					.font(.title3.weight(.semibold))
					.multilineTextAlignment(.center)
					.textFieldStyle(.roundedBorder)
					.submitLabel(.done)
					.padding(.horizontal, 14)
					.padding(.vertical, 14)
			}
			.padding(.horizontal, 18)
			.padding(.vertical, 22)
			.frame(maxWidth: .infinity)
		}
		.listSectionMargins(.top, 0)
    }

    private var colorPicker: some View {
		Section("Colour") {
			LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 15), count: 6), spacing: 15) {
				ForEach(colors, id: \.self) { color in
					Button {
						colorHex = color
					} label: {
						Circle()
							.fill(Color(hex: color))
							.frame(width: 42, height: 42)
							.overlay {
								if colorHex == color {
									Circle().stroke(Color.primary.opacity(0.8), lineWidth: 2).padding(-5)
									Image(systemName: "checkmark")
										.font(.caption.weight(.bold))
										.foregroundStyle(.white)
								}
							}
					}
					.buttonStyle(.plain)
					.accessibilityLabel("Color \(color)")
					.accessibilityAddTraits(colorHex == color ? .isSelected : [])
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
    }

    private var iconPicker: some View {
		Section("Icon") {
			LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
				ForEach(icons, id: \.self) { icon in
					Button {
						iconName = icon
					} label: {
						Image(systemName: icon)
							.font(.system(size: 18, weight: .medium))
							.foregroundStyle(iconName == icon ? .white : Color(hex: colorHex))
							.frame(maxWidth: .infinity)
							.frame(width: 53, height: 53)
							.background(
								iconName == icon ? Color(hex: colorHex) : Color(uiColor: .tertiarySystemGroupedBackground),
								in: Circle()
							)
					}
					.buttonStyle(.plain)
					.accessibilityLabel(icon.replacingOccurrences(of: ".fill", with: "").replacingOccurrences(of: ".", with: " "))
					.accessibilityAddTraits(iconName == icon ? .isSelected : [])
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), radix: 16) ?? 0x007AFF
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}
