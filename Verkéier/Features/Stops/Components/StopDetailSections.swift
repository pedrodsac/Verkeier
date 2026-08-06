import SwiftUI

struct PlatformFilterPicker: View {
    let platforms: [String]
    let selectedPlatform: String?
    let selectPlatform: (String?) -> Void

    var body: some View {
        if !platforms.isEmpty {
            Picker(
                "Platform",
                selection: Binding(
                    get: { selectedPlatform ?? "" },
                    set: { selectPlatform($0.isEmpty ? nil : $0) }
                )
            ) {
                Text("All").tag("")
                ForEach(platforms, id: \.self) { platform in
                    Text(platform).tag(platform)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Platform filter")
        }
    }
}

struct StopDisruptionSection: View {
    let alerts: [AlertMessage]

    var body: some View {
        if !alerts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Disruption Impact")
                    .font(.headline.weight(.semibold))
                Text("These AVL alerts affect this stop or its served lines.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(alerts.prefix(3)) { alert in
                    CompactAlertRow(alert: alert)
                }
            }
        }
    }
}

private struct CompactAlertRow: View {
    let alert: AlertMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(alert.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text(alert.body)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Shared loading card used across the stop-detail, route, and commute surfaces.
struct DepartureLoadingCard: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Shared empty/error card used across the stop-detail, route, and line surfaces.
struct CompactUnavailableCard: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(.secondary.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    DepartureLoadingCard(title: "Loading departures")
}

#Preview(traits: .sizeThatFitsLayout) {
    CompactUnavailableCard(
        title: "No departures",
        message: "No live departures are available for this stop.",
        systemImage: "clock.badge.exclamationmark"
    )
}
