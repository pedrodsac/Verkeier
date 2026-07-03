import SwiftUI

// MARK: - RouteLegList

/// The place-centric vertical timeline for a selected route: an alternating list
/// of place rows (markers) and segment rows (walk / transfer / ride), joined by a
/// continuous rail and grouped on one card. Flattened from the legs by
/// ``RouteTimelineBuilder``; the row and rail views live in their own files.
struct RouteLegList: View {
    let legs: [RoutePlan.Leg]
    /// Active disruptions per transit leg, keyed by leg index string (matching
    /// ``RouteTimelineBuilder`` segment ids "segment-<index>").
    var legAlerts: [String: [AlertMessage]] = [:]

    private var items: [RouteTimelineItem] {
        RouteTimelineBuilder.items(from: legs)
    }

    private var alertsBySegmentID: [String: [AlertMessage]] {
        Dictionary(uniqueKeysWithValues: legAlerts.map { ("segment-\($0.key)", $0.value) })
    }

    var body: some View {
        if !items.isEmpty {
            VStack(spacing: 0) {
                ForEach(items) { item in
                    switch item {
                    case let .place(node):
                        TimelinePlaceRow(node: node)
                    case let .segment(node):
                        TimelineSegmentRow(node: node, alerts: alertsBySegmentID[node.id] ?? [])
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .cardSurface(radius: Radius.card)
        }
    }
}

// MARK: - Previews

#if DEBUG

    private let previewOrigin = LocationPoint(
        id: "origin",
        name: "Current Location",
        latitude: 49.6116,
        longitude: 6.1319
    )
    private let previewHamilius = LocationPoint(id: "hamilius", name: "Hamilius", latitude: 49.6111, longitude: 6.1275)
    private let previewKirchberg = LocationPoint(
        id: "kirchberg",
        name: "Kirchberg P+R",
        latitude: 49.6260,
        longitude: 6.1600
    )
    private let previewLuxexpo = LocationPoint(id: "luxexpo", name: "Luxexpo", latitude: 49.6329, longitude: 6.1746)

    private let previewWalkLeg = RoutePlan.Leg(
        id: "walk1",
        mode: .walking,
        instruction: "Walk to Hamilius",
        transportKind: .walking,
        origin: previewOrigin,
        destination: previewHamilius,
        departureTime: Date(),
        arrivalTime: Date().addingTimeInterval(4 * 60),
        distanceMeters: 320
    )

    private let previewTramLeg = RoutePlan.Leg(
        id: "tram1",
        mode: .tram,
        instruction: "Take tram T1 toward Luxexpo",
        transportKind: .transit,
        routeName: "T1",
        headsign: "Luxexpo, Pôle d'Échange",
        origin: previewHamilius,
        destination: previewKirchberg,
        departureTime: Date().addingTimeInterval(6 * 60),
        arrivalTime: Date().addingTimeInterval(14 * 60),
        realtimeDepartureTime: Date().addingTimeInterval(7 * 60),
        realtimeArrivalTime: Date().addingTimeInterval(15 * 60),
        platform: "2",
        delayMinutes: 1,
        liveStatus: .live
    )

    private let previewBusLeg = RoutePlan.Leg(
        id: "bus1",
        mode: .bus,
        instruction: "Take bus 16 toward Luxexpo",
        transportKind: .transit,
        routeName: "16",
        headsign: "Luxexpo, Gare routière",
        origin: previewKirchberg,
        destination: previewLuxexpo,
        departureTime: Date().addingTimeInterval(16 * 60),
        arrivalTime: Date().addingTimeInterval(22 * 60),
        platform: "3",
        liveStatus: .scheduled,
        transferWarning: "Only 1 min to transfer"
    )

    private let previewFinalWalkLeg = RoutePlan.Leg(
        id: "walk2",
        mode: .walking,
        instruction: "Walk to Luxexpo entrance",
        transportKind: .walking,
        origin: previewLuxexpo,
        destination: LocationPoint(id: "dest", name: "Luxexpo", latitude: 49.6335, longitude: 6.1755),
        departureTime: Date().addingTimeInterval(22 * 60),
        arrivalTime: Date().addingTimeInterval(24 * 60),
        distanceMeters: 110
    )

    private let previewTramPlan = RoutePlan(
        id: "tram-plan",
        origin: previewOrigin,
        destination: previewLuxexpo,
        expectedTravelTime: 24 * 60,
        distanceMeters: 4500,
        legs: [previewWalkLeg, previewTramLeg, previewBusLeg, previewFinalWalkLeg],
        dataSource: .mock
    )

    private let previewTramOption = RouteOption(
        id: "tram-route",
        plan: previewTramPlan,
        mapOverlay: nil
    )

    private let previewDelayedOption = RouteOption(
        id: "delayed-route",
        plan: RoutePlan(
            id: "delayed-plan",
            origin: previewOrigin,
            destination: previewLuxexpo,
            expectedTravelTime: 30 * 60,
            distanceMeters: 4800,
            legs: [
                previewWalkLeg,
                RoutePlan.Leg(
                    id: "delayed-tram",
                    mode: .tram,
                    instruction: "Take tram T1 toward Luxexpo",
                    transportKind: .transit,
                    routeName: "T1",
                    headsign: "Luxexpo, Pôle d'Échange",
                    origin: previewHamilius,
                    destination: previewLuxexpo,
                    departureTime: Date().addingTimeInterval(6 * 60),
                    arrivalTime: Date().addingTimeInterval(28 * 60),
                    realtimeDepartureTime: Date().addingTimeInterval(12 * 60),
                    realtimeArrivalTime: Date().addingTimeInterval(30 * 60),
                    delayMinutes: 6,
                    liveStatus: .delayed
                )
            ],
            dataSource: .mock
        ),
        mapOverlay: nil
    )

    #Preview("Summary Card – Live", traits: .sizeThatFitsLayout) {
        RouteTimelineSummaryCard(option: previewTramOption)
            .padding()
            .background(Color(uiColor: .systemGroupedBackground))
    }

    #Preview("Summary Card – Delayed", traits: .sizeThatFitsLayout) {
        RouteTimelineSummaryCard(option: previewDelayedOption)
            .padding()
            .background(Color(uiColor: .systemGroupedBackground))
    }

    #Preview("Timeline – Walk + Tram + Bus + Walk", traits: .sizeThatFitsLayout) {
        ScrollView {
            RouteLegList(legs: [previewWalkLeg, previewTramLeg, previewBusLeg, previewFinalWalkLeg])
                .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    #Preview("Timeline – Delayed", traits: .sizeThatFitsLayout) {
        RouteLegList(legs: previewDelayedOption.plan.legs)
            .padding()
            .background(Color(uiColor: .systemGroupedBackground))
    }

    #Preview("Timeline – Long names", traits: .sizeThatFitsLayout) {
        let longHamilius = LocationPoint(
            id: "ham-long",
            name: "Luxembourg, Hamilius — Centre Quai 3 Direction Kirchberg",
            latitude: 49.6111,
            longitude: 6.1275
        )
        let walk = RoutePlan.Leg(
            id: "lw",
            mode: .walking,
            instruction: "Walk",
            transportKind: .walking,
            origin: LocationPoint(
                id: "o-long",
                name: "Senningerberg, Breedewues Gare Routière Sud",
                latitude: 49.6116,
                longitude: 6.1319
            ),
            destination: longHamilius,
            departureTime: Date(),
            arrivalTime: Date().addingTimeInterval(4 * 60),
            distanceMeters: 320
        )
        let tram = RoutePlan.Leg(
            id: "lt",
            mode: .tram,
            instruction: "Tram",
            transportKind: .transit,
            routeName: "T1",
            origin: longHamilius,
            destination: previewKirchberg,
            departureTime: Date().addingTimeInterval(6 * 60),
            arrivalTime: Date().addingTimeInterval(14 * 60),
            platform: "2",
            liveStatus: .scheduled
        )
        return ScrollView {
            RouteLegList(legs: [walk, tram, previewFinalWalkLeg]).padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

#endif
