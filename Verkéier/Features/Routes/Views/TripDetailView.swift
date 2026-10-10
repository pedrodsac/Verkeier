import SwiftUI

struct TripDetailView: View {
    let selection: TripDetailSelection
    let viewModel: TripDetailViewModel
    let refresh: () async -> Void
    @State private var scrolledSelection: TripDetailSelection?

    var body: some View {
        ScrollViewReader { proxy in
            stopList
                .task(id: initialScrollTarget) {
                    guard let target = initialScrollTarget else { return }
                    // Let the loaded native rows register their scroll identities.
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    proxy.scrollTo(target.boardingSequence, anchor: .top)
                    scrolledSelection = target
                }
        }
    }

    private var initialScrollTarget: TripDetailSelection? {
        guard scrolledSelection != selection, viewModel.selection == selection,
              viewModel.rows.contains(where: { $0.id == selection.boardingSequence }) else { return nil }
        return selection
    }

    private var stopList: some View {
        List {
            if let snapshot = viewModel.snapshot {
                Section {
                    if let message = viewModel.errorMessage {
                        Label(message, systemImage: "wifi.exclamationmark")
							.foregroundStyle(.secondary)
                    }
                }
                Section {
                    ForEach(viewModel.rows) { row in
						if row.isInRide {
							TripStopRow(row: row)
								.id(row.id)
								.listRowBackground(selection.mode.tint.opacity(0.10))
						} else if row.isPassed {
							TripStopRow(row: row)
								.id(row.id)
								.listRowBackground(Color(uiColor: .secondarySystemFill))
						} else {
							TripStopRow(row: row)
								.id(row.id)
						}
                    }
                } footer: {
                    if snapshot.isApproximateRoute {
                        Text("The dashed line connects stops. The exact route path is unavailable.")
                    }
                }
            } else if viewModel.isLoading {
                HStack {
                    ProgressView()
                    Text("Loading stops…").foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView {
                    Label("Stop details unavailable", systemImage: "bus.fill")
                } description: {
                    Text(viewModel.errorMessage ?? "This run has no available stop details.")
                } actions: {
                    Button("Try again") { Task { await refresh() } }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await refresh() }
		.navigationTitle("\(selection.lineName): \(selection.headsign ?? "Destination unknown")")
        .toolbarTitleDisplayMode(.inline)
    }
}

private struct TripStopRow: View {
    let row: TripStopRowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
			HStack(alignment: .center) {
				stopName
					.lineLimit(1)
					.minimumScaleFactor(0.8)
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
