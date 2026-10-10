#if DEBUG && targetEnvironment(simulator)
import MapKit
import SwiftUI

/// Explicit fixture host for previews and simulator inspection. Never selected
/// during normal launch and never substituted for production transit data.
@MainActor
enum TripDetailPreviewData {
    static var enabled: Bool { CommandLine.arguments.contains("--trip-detail-preview") }
    static let now = Date()
    static let names = ["Howald", "Gare Centrale", "Hamilius", "Fondation Pescatore", "Kirchberg", "Luxexpo", "Aéroport Luxembourg/Findel"]
    static let points: [RouteMapCoordinate] = [
        .init(latitude: 49.58, longitude: 6.13), .init(latitude: 49.599, longitude: 6.134),
        .init(latitude: 49.611, longitude: 6.128), .init(latitude: 49.617, longitude: 6.132),
        .init(latitude: 49.623, longitude: 6.155), .init(latitude: 49.636, longitude: 6.174),
        .init(latitude: 49.634, longitude: 6.215)
    ]
    static var leg: RoutePlan.Leg {
        var leg = RoutePlan.Leg(id: "preview-850", mode: .bus, transportKind: .transit,
            routeName: "850", headsign: names.last, origin: location(1), destination: location(4),
            departureTime: now.addingTimeInterval(-120), arrivalTime: now.addingTimeInterval(600),
            mapCoordinates: Array(points[1...4]))
        leg.tripInstance = .init(feedGeneration: 1, tripID: "preview-run", serviceDate: "20261009")
        leg.routeShortName = "850"
        leg.boardingStopSequence = 2
        leg.alightingStopSequence = 5
        return leg
    }
    static var selection: TripDetailSelection { TripDetailSelection(leg: leg)! }
    static var snapshot: TripDetailSnapshot {
        let stops = names.enumerated().map { index, name in
            let planned = now.addingTimeInterval(Double(index - 2) * 240)
            let delay = index == 0 ? 60.0 : index == 1 ? 120 : 180
            let timing = TripStopTiming(scheduled: planned,
                realtime: index == 5 ? nil : planned.addingTimeInterval(delay),
                isHistoricalReport: index < 2, observedAt: now, isCancelled: false)
            return TripStopEntry(sequence: index + 1,
                stop: .init(id: "sample-\(index)", name: name, location: location(index), modes: [.bus], dataSource: .mock),
                arrival: timing, departure: timing, platform: index == 1 ? "3" : nil)
        }
        return .init(instance: selection.instance, stops: stops,
            mapOverlay: RouteMapOverlayBuilder.trip(segments: [
                .init(id: "full-run", mode: .bus, routeId: "preview", coordinates: points, emphasis: .context, isApproximate: true, routeShortName: "850"),
                .init(id: "your-ride", mode: .bus, routeId: "preview", coordinates: Array(points[1...4]), emphasis: .highlighted, isApproximate: true, routeShortName: "850")
            ], stops: stops, selection: selection), isApproximateRoute: true, liveDataAvailable: true, isCancelled: false, fetchedAt: now)
    }
    private static func location(_ index: Int) -> LocationPoint {
        .init(name: names[index], latitude: points[index].latitude, longitude: points[index].longitude)
    }
}

struct TripDetailPreviewHost: View {
    @State private var model = TripDetailViewModel()
    @State private var path: [TransitSheetRoute] = []
    @State private var presented = false
    @State private var detent = BottomSheetDetent.mediumPresentationDetent
    private let service = FixtureTripDetailService(snapshot: TripDetailPreviewData.snapshot)

    var body: some View {
        TransitMapView(state: .init(
            region: MKCoordinateRegion(center: .init(latitude: 49.59, longitude: 6.17),
                span: .init(latitudeDelta: 0.15, longitudeDelta: 0.15)), cameraUpdateToken: 1,
            liveStops: [], gtfsStops: [], selectedStopId: nil, favouriteStopIds: [], alertStopIds: [],
            bikeShareStations: [], routeOverlay: path.isEmpty ? nil : model.snapshot?.mapOverlay, hideMapPins: true),
            selectStop: { _ in }, selectStopGroup: { _, _ in }, regionDidChange: { _ in })
        .ignoresSafeArea()
        .onAppear { presented = true }
        .sheet(isPresented: $presented) {
            NavigationStack(path: $path) {
                VStack(spacing: 20) {
                    Text("Sample bus run").font(.caption).foregroundStyle(.secondary)
                    RouteLegList(legs: [TripDetailPreviewData.leg])
                    Spacer()
                }
                .padding(16)
                .navigationTitle("Selected route")
                .toolbarTitleDisplayMode(.inline)
                .navigationDestination(for: TransitSheetRoute.self) { route in
                    if case let .tripDetail(selection) = route {
                        TripDetailView(selection: selection, viewModel: model) {
                            await model.refresh(using: service)
                        }
                        .task { await model.observe(selection, using: service) }
                    }
                }
            }
            .dynamicTypeSize(CommandLine.arguments.contains("--trip-detail-accessibility") ? .accessibility3 : .large)
            .presentationDetents(BottomSheetDetent.presentationDetents, selection: $detent)
            .presentationBackgroundInteraction(.enabled(upThrough: BottomSheetDetent.mediumPresentationDetent))
            .interactiveDismissDisabled()
        }
    }
}

#Preview("Whole bus run — sample data") {
    TripDetailPreviewHost().environment(AppPreferences())
}
#endif
