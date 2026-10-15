import SwiftUI

/// Every stop of one vehicle run, scrolled to where the rider boards.
struct TripDetailScreen: View {
    @Environment(TripDetailModel.self) private var model
    @Environment(\.tripDetailService) private var tripDetailService

    let selection: TripDetailSelection

    @State private var scrolledSelection: TripDetailSelection?

    var body: some View {
        ScrollViewReader { proxy in
            stopList
                .task(id: initialScrollTarget) {
                    guard let target = initialScrollTarget else { return }
                    // Let the loaded native rows register their scroll identities.
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    proxy.scrollTo(
                        TripStopOccurrenceIdentity(instance: target.instance, sequence: target.boardingSequence),
                        anchor: .top
                    )
                    scrolledSelection = target
                }
        }
    }

    private var initialScrollTarget: TripDetailSelection? {
        guard scrolledSelection != selection, model.selection == selection,
            model.rows.contains(where: { $0.id == selection.boardingSequence })
        else { return nil }
        return selection
    }

    private var stopList: some View {
        List {
            if let snapshot = model.snapshot {
                if let message = model.errorMessage {
                    Section {
                        Label(message, systemImage: "wifi.exclamationmark")
                            .foregroundStyle(.secondary)
                    }
                    .listSectionMargins(.top, 10)
                }
                Section {
                    ForEach(model.rows) { row in
                        if row.isInRide {
                            TripStopRow(row: row)
                                .id(TripStopOccurrenceIdentity(instance: selection.instance, sequence: row.id))
                                .listRowBackground(selection.mode.tint.opacity(0.10))
                        } else if row.isPassed {
                            TripStopRow(row: row)
                                .id(TripStopOccurrenceIdentity(instance: selection.instance, sequence: row.id))
                                .listRowBackground(Color(uiColor: .secondarySystemFill))
                        } else {
                            TripStopRow(row: row)
                                .id(TripStopOccurrenceIdentity(instance: selection.instance, sequence: row.id))
                        }
                    }
                }
                .listSectionMargins(.top, model.errorMessage == nil ? 10 : nil)
                ForEach(model.continuations) { continuation in
                    Section {
                        ForEach(continuation.rows) { row in
                            TripStopRow(row: row)
                                .id(TripStopOccurrenceIdentity(instance: continuation.id, sequence: row.id))
                                .listRowBackground(
                                    row.isInRide
                                        ? continuation.mode.tint.opacity(0.10)
                                        : row.isPassed ? Color(uiColor: .secondarySystemFill) : nil
                                )
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 4) {
                            if let headsign = continuation.headsign?.stationDisplayName(
                                hidingLocality: continuation.mode == .tram
                            ) {
                                Text("Continues as \(continuation.lineName): \(headsign)")
                                    .lineLimit(1)
                            } else {
                                Text("Continues as \(continuation.lineName)")
                            }
                        }
                        .textCase(nil)
                        .font(.caption)
                    }
                    .listSectionMargins(.top, -15)
                }
                if snapshot.isApproximateRoute {
                    Section {
                        Text("The dashed line connects stops. The exact route path is unavailable.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } else if model.isLoading {
                HStack {
                    ProgressView()
                    Text("Loading stops…").foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView {
                    Label("Stop details unavailable", systemImage: "bus.fill")
                } description: {
                    Text(model.errorMessage ?? "This run has no available stop details.")
                } actions: {
                    Button("Try again") { Task { await model.refresh(using: tripDetailService) } }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await model.refresh(using: tripDetailService) }
        .navigationTitle(
            "\(selection.lineName): \(selection.headsign?.stationDisplayName(hidingLocality: selection.mode == .tram) ?? "Destination unknown")"
        )
        .toolbarTitleDisplayMode(.inline)
    }
}

private struct TripStopRow: View {
    let row: TripStopItem

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center) {
                stopName
                Spacer(minLength: 12)
                times
            }
            HStack(alignment: .center) {
                Text(row.platform.map { "Platform \($0)" } ?? "Platform unavailable")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if row.status != "Live time unavailable" {
                    Text(row.status).font(.caption.weight(.medium))
                        .foregroundStyle(statusColor)
                        .accessibilityLabel(row.accessibilityStatus)
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityValue(row.isInRide ? "Part of your ride" : "")
    }

    private var stopName: some View {
        Text(row.name).font(.body.weight(row.isInRide ? .semibold : .regular))
            .foregroundStyle(row.isPassed ? .secondary : .primary)
            .fixedSize(horizontal: false, vertical: true)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var times: some View {
        HStack(spacing: 5) {
            if let scheduled = row.scheduledTime {
                Text(scheduled, style: .time)
                    .foregroundStyle(row.isPassed || row.liveTime != nil ? .secondary : .primary)
                    .strikethrough(row.liveTime != nil)
            }
            if let live = row.liveTime {
                Text(live, style: .time)
                    .fontWeight(.semibold)
                    .foregroundStyle(statusColor)
            }
        }
        .font(.subheadline).monospacedDigit()
        .fixedSize(horizontal: true, vertical: false)
    }

    private var statusColor: Color {
        switch row.statusTint {
        case .green: .green
        case .orange: .orange
        case .red: .red
        case .secondary: .secondary
        }
    }
}
