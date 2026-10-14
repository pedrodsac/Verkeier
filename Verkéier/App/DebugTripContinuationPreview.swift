#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Explicit sample data for inspecting a route-number change, never a normal launch mode.
@MainActor
struct TripContinuationPreviewHost: View {
    static var enabled: Bool { CommandLine.arguments.contains("--trip-continuation-preview") }
    @State private var model = TripDetailViewModel()
    private let selection: TripDetailSelection
    private let service: FixtureTripDetailService

    init() {
        let now = Date.now
        let first = TripDetailSelection(
            instance: .init(feedGeneration: 1, tripID: "sample-7", serviceDate: "20261010"),
            boardingSequence: 1,
            alightingSequence: 2,
            lineName: "7",
            routeShortName: "7",
            headsign: "Kirchberg, Poutty Stein",
            mode: .bus,
            routeID: "sample-7"
        )
        let next = TripDetailSelection(
            instance: .init(feedGeneration: 1, tripID: "sample-25", serviceDate: "20261010"),
            boardingSequence: 1,
            alightingSequence: 6,
            lineName: "25",
            routeShortName: "25",
            headsign: "Dommeldange, Gare routière",
            mode: .bus,
            routeID: "sample-25"
        )
        func stop(_ sequence: Int, _ name: String, _ seconds: Double) -> TripStopEntry {
            let time = now.addingTimeInterval(seconds)
            let timing = TripStopTiming(
                scheduled: time,
                realtime: time,
                isHistoricalReport: false,
                observedAt: now,
                isCancelled: false
            )
            return .init(
                sequence: sequence,
                stop: .init(
                    id: "sample-\(name)",
                    name: name,
                    location: .init(latitude: 49.63, longitude: 6.17),
                    modes: [.bus],
                    dataSource: .mock
                ),
                arrival: timing,
                departure: timing,
                platform: "5"
            )
        }
        let child = TripDetailSnapshot(
            instance: next.instance,
            stops: [
                stop(1, "Kirchberg, Poutty Stein", 230), stop(2, "Kirchberg, Chambre des Métiers", 280),
                stop(3, "Kirchberg, Réimerwee", 300), stop(4, "Kirchberg, Albert Borschette", 370),
                stop(5, "Kirchberg, Coudenhove-Kalergi", 410), stop(6, "Kirchberg, prov. Konrad Adenauer", 470),
            ],
            mapOverlay: .init(segments: []),
            isApproximateRoute: false,
            liveDataAvailable: true,
            isCancelled: false,
            fetchedAt: now
        )
        let root = TripDetailSnapshot(
            instance: first.instance,
            stops: [
                stop(1, "Kirchberg, Gare routière Luxexpo", 120), stop(2, "Kirchberg, Poutty Stein", 200),
            ],
            mapOverlay: .init(segments: []),
            isApproximateRoute: false,
            liveDataAvailable: true,
            isCancelled: false,
            fetchedAt: now,
            continuations: [.init(selection: next, snapshot: child)]
        )
        selection = first
        service = FixtureTripDetailService(snapshot: root)
    }

    var body: some View {
        NavigationStack {
            TripDetailView(selection: selection, viewModel: model) {
                await model.refresh(using: service)
            }
            .safeAreaInset(edge: .top) { Text("Sample data").font(.caption).foregroundStyle(.secondary) }
            .dynamicTypeSize(CommandLine.arguments.contains("--trip-detail-accessibility") ? .accessibility3 : .large)
        }
        .task { await model.observe(selection, using: service) }
    }
}

#Preview("Bus 7 continues as 25 — sample data") {
    TripContinuationPreviewHost()
}
#endif
