#if DEBUG && targetEnvironment(simulator)
import MapKit
import SwiftUI

/// Explicit sample geometry only. Never used as a production data fallback.
@MainActor
enum RouteTracePreviewData {
    enum Scenario: String, CaseIterable, Identifiable {
        case journey, loop, transfer, trip
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    static var enabled: Bool { CommandLine.arguments.contains("--map-trace-preview") }
    static var initialScenario: Scenario {
        guard let index = CommandLine.arguments.firstIndex(of: "--trace-scenario"),
              index + 1 < CommandLine.arguments.count else { return .journey }
        return Scenario(rawValue: CommandLine.arguments[index + 1]) ?? .journey
    }

    static let points: [RouteMapCoordinate] = [
        .init(latitude: 49.6360, longitude: 6.1760), .init(latitude: 49.6356, longitude: 6.1772),
        .init(latitude: 49.6357, longitude: 6.1781), .init(latitude: 49.6363, longitude: 6.1800),
        .init(latitude: 49.6375, longitude: 6.1810), .init(latitude: 49.6384, longitude: 6.1828),
        .init(latitude: 49.6392, longitude: 6.1854), .init(latitude: 49.6396, longitude: 6.1890),
        .init(latitude: 49.6401, longitude: 6.1940), .init(latitude: 49.6407, longitude: 6.2010),
        .init(latitude: 49.6411, longitude: 6.2100), .init(latitude: 49.6413, longitude: 6.2140),
        .init(latitude: 49.6418, longitude: 6.2155), .init(latitude: 49.6419, longitude: 6.2165),
        .init(latitude: 49.6415, longitude: 6.2175), .init(latitude: 49.6417, longitude: 6.2186),
        .init(latitude: 49.6424, longitude: 6.2200), .init(latitude: 49.6432, longitude: 6.2210),
        .init(latitude: 49.6444, longitude: 6.2216), .init(latitude: 49.6450, longitude: 6.2230),
        .init(latitude: 49.6451, longitude: 6.2250), .init(latitude: 49.6448, longitude: 6.2270)
    ]
    static let stopIndices = [0, 6, 16, 21]
    static let names = ["Kirchberg, Gare routière Luxexpo", "Senningerberg, Kapell",
                        "Senningerberg, Rue du Golf", "Senningerberg, Gromscheed"]
    static let overlays: [Scenario: RouteMapOverlay] = [
        .journey: journey(), .loop: loop(), .transfer: transfer(), .trip: trip()
    ]

    static func region(for scenario: Scenario) -> MKCoordinateRegion {
        if scenario == .loop {
            return .init(center: .init(latitude: 49.643, longitude: 6.219),
                span: .init(latitudeDelta: 0.010, longitudeDelta: 0.016))
        }
        return .init(center: .init(latitude: 49.637, longitude: 6.202),
            span: .init(latitudeDelta: 0.025, longitudeDelta: 0.072))
    }

    private static func stop(_ index: Int) -> RouteStopOccurrence {
        .init(id: "visit-\(index)", stopID: "sample-stop-\(index)", name: names[index], coordinate: points[stopIndices[index]])
    }

    private static func ride(_ id: String, number: String, range: ClosedRange<Int>, stops: [RouteStopOccurrence]) -> RoutePlan.Leg {
        .init(id: id, mode: .bus, transportKind: .transit, routeName: "Sample bus \(number)",
            originStopId: stops.first?.stopID, destinationStopId: stops.last?.stopID,
            origin: location(points[range.lowerBound]), destination: location(points[range.upperBound]),
            mapCoordinates: Array(points[range]), mapStops: stops, routeShortName: number)
    }

    private static func journey() -> RouteMapOverlay {
        let bus = ride("bus-322", number: "322", range: 0...21, stops: (0...3).map(stop))
        let home = RouteMapCoordinate(latitude: 49.649, longitude: 6.225)
        let walk = RoutePlan.Leg(id: "walk", mode: .walking, transportKind: .walking,
            origin: bus.destination, destination: location(home), mapCoordinates: [points[21],
                .init(latitude: 49.6456, longitude: 6.2272), .init(latitude: 49.6480, longitude: 6.2272),
                .init(latitude: 49.6488, longitude: 6.2273), home])
        return RouteMapOverlayBuilder.itinerary(legs: [bus, walk])
    }

    private static func loop() -> RouteMapOverlay {
        let start = RouteMapCoordinate(latitude: 49.6417, longitude: 6.215)
        let coordinates = [start, .init(latitude: 49.6430, longitude: 6.217),
            .init(latitude: 49.6450, longitude: 6.220), .init(latitude: 49.6458, longitude: 6.223),
            .init(latitude: 49.6457, longitude: 6.225), .init(latitude: 49.6452, longitude: 6.226),
            .init(latitude: 49.6445, longitude: 6.2258), .init(latitude: 49.6442, longitude: 6.224),
            .init(latitude: 49.6444, longitude: 6.220), .init(latitude: 49.6449, longitude: 6.214),
            .init(latitude: 49.6451, longitude: 6.210)]
        return RouteMapOverlayBuilder.line(segment: .init(id: "loop", mode: .bus, coordinates: coordinates, routeShortName: "850"),
            stops: [.init(id: "first", stopID: "first", name: "Senningerberg, Héienhaff", coordinate: start),
                    .init(id: "last", stopID: "last", name: "Sample terminus", coordinate: coordinates.last!)])
    }

    private static func transfer() -> RouteMapOverlay {
        RouteMapOverlayBuilder.itinerary(legs: [
            ride("first", number: "322", range: 0...16, stops: (0...2).map(stop)),
            ride("second", number: "850", range: 16...21, stops: (2...3).map(stop))
        ])
    }

    private static func trip() -> RouteMapOverlay {
        var leg = ride("ride", number: "322", range: 6...16, stops: (1...2).map(stop))
        leg.tripInstance = .init(feedGeneration: 1, tripID: "sample", serviceDate: "20261010")
        leg.boardingStopSequence = 1
        leg.alightingStopSequence = 2
        let selection = TripDetailSelection(leg: leg)!
        let entries = (0...3).map { index in
            TripStopEntry(sequence: index, stop: .init(id: "sample-\(index)", name: names[index],
                location: location(points[stopIndices[index]]), modes: [.bus], dataSource: .mock),
                arrival: nil, departure: nil, platform: nil)
        }
        return RouteMapOverlayBuilder.trip(segments: [
            .init(id: "full-run", mode: .bus, routeId: "sample", coordinates: points, emphasis: .context, routeShortName: "322"),
            .init(id: "your-ride", mode: .bus, routeId: "sample", coordinates: Array(points[6...16]), emphasis: .highlighted, routeShortName: "322")
        ], stops: entries, selection: selection)
    }

    private static func location(_ point: RouteMapCoordinate) -> LocationPoint {
        .init(latitude: point.latitude, longitude: point.longitude)
    }
}

struct RouteTracePreviewHost: View {
    @State private var scenario = RouteTracePreviewData.initialScenario
    @State private var cameraToken = 0
    @State private var presented = false
    @State private var detent = PresentationDetent.fraction(0.22)

    var body: some View {
        TransitMapView(state: .init(region: RouteTracePreviewData.region(for: scenario), cameraUpdateToken: cameraToken,
            liveStops: [], gtfsStops: [], selectedStopId: nil, favouriteStopIds: [], alertStopIds: [], bikeShareStations: [],
            routeOverlay: RouteTracePreviewData.overlays[scenario], hideMapPins: true),
            selectStop: { _ in }, selectStopGroup: { _, _ in }, regionDidChange: { _ in })
        .ignoresSafeArea()
        .onChange(of: scenario) { cameraToken += 1 }
        .onAppear { presented = true }
        .sheet(isPresented: $presented) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Map trace design").font(.title2.bold())
                Text("Sample routes and geometry • No live transit data").font(.caption).foregroundStyle(.secondary)
                Picker("Sample route", selection: $scenario) {
                    ForEach(RouteTracePreviewData.Scenario.allCases) { value in Text(value.title).tag(value) }
                }
                .pickerStyle(.segmented)
                Spacer()
            }
            .padding(24)
            .presentationDetents([.fraction(0.22), .medium, .large], selection: $detent)
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .interactiveDismissDisabled()
        }
    }
}

#Preview("Map traces — sample routes") { RouteTracePreviewHost() }
#Preview("Map traces — dark") { RouteTracePreviewHost().preferredColorScheme(.dark) }
#Preview("Map traces — large text") { RouteTracePreviewHost().dynamicTypeSize(.accessibility3) }
#endif
