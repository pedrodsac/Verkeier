import Foundation

struct FixtureATPClient: ATPClient {
    enum Mode: Sendable {
        case sample
        case empty
        case failure
        case disruption
    }

    let mode: Mode
    let now: @Sendable () -> Date

    init(mode: Mode, now: @escaping @Sendable () -> Date = { .now }) {
        self.mode = mode
        self.now = now
    }

    nonisolated func nearbyStops(latitude: Double, longitude: Double) async throws -> [Stop] {
        switch mode {
        case .sample, .disruption:
            return Self.sampleStops
        case .empty:
            return []
        case .failure:
            throw ATPClientError.invalidResponse
        }
    }

    nonisolated func departureBoard(stopId: String) async throws -> [Departure] {
        switch mode {
        case .sample:
            return Self.sampleDepartures(now: now())[stopId] ?? []
        case .disruption:
            return Self.disruptionDepartures(now: now())[stopId] ?? []
        case .empty:
            return []
        case .failure:
            throw ATPClientError.invalidResponse
        }
    }

    private static var sampleStops: [Stop] {
        [
            Stop(
                id: "sample-hamilius",
                name: "Hamilius",
                locality: "Luxembourg",
                location: LocationPoint(name: "Hamilius", latitude: 49.6112, longitude: 6.1277),
                modes: [.bus, .tram],
                dataSource: .mock,
                platformIds: ["sample-hamilius-a", "sample-hamilius-b"]
            ),
            Stop(
                id: "sample-gare",
                name: "Gare Centrale",
                locality: "Luxembourg",
                location: LocationPoint(name: "Gare Centrale", latitude: 49.6003, longitude: 6.1335),
                modes: [.train, .tram, .bus],
                dataSource: .mock,
                platformIds: ["sample-gare-1"]
            ),
            Stop(
                id: "sample-philharmonie",
                name: "Philharmonie",
                locality: "Kirchberg",
                location: LocationPoint(name: "Philharmonie", latitude: 49.6206, longitude: 6.1438),
                modes: [.tram, .bus],
                dataSource: .mock,
                platformIds: ["sample-phil-1"]
            )
        ]
    }

    private static func sampleDepartures(now: Date) -> [String: [Departure]] {
        [
            "sample-hamilius": [
                sampleDeparture(
                    id: "sample-hamilius-4",
                    stopId: "sample-hamilius",
                    routeId: "route-4",
                    lineName: "4",
                    destination: "Leudelange",
                    minutesFromNow: 3,
                    platform: "A"
                ),
                sampleDeparture(
                    id: "sample-hamilius-t1",
                    stopId: "sample-hamilius",
                    routeId: "route-t1",
                    lineName: "T1",
                    destination: "Luxexpo",
                    minutesFromNow: 8,
                    platform: "Tram"
                )
            ],
            "sample-gare": [
                sampleDeparture(
                    id: "sample-gare-10",
                    stopId: "sample-gare",
                    routeId: "route-10",
                    lineName: "10",
                    destination: "Findel",
                    minutesFromNow: 5,
                    platform: "1"
                )
            ],
            "sample-philharmonie": [
                sampleDeparture(
                    id: "sample-phil-16",
                    stopId: "sample-philharmonie",
                    routeId: "route-16",
                    lineName: "16",
                    destination: "Howald",
                    minutesFromNow: 7,
                    platform: "B"
                )
            ]
        ].mapValues { departures in
            departures.map { departure in
                departure.resolved(at: now)
            }
        }
    }

    private static func disruptionDepartures(now: Date) -> [String: [Departure]] {
        [
            "sample-hamilius": [
                sampleDeparture(
                    id: "sample-hamilius-4-delayed",
                    stopId: "sample-hamilius",
                    routeId: "route-4",
                    lineName: "4",
                    destination: "Leudelange",
                    minutesFromNow: 2,
                    delayMinutes: 7,
                    platform: "A"
                ),
                sampleDeparture(
                    id: "sample-hamilius-t1-cancelled",
                    stopId: "sample-hamilius",
                    routeId: "route-t1",
                    lineName: "T1",
                    destination: "Luxexpo",
                    minutesFromNow: 9,
                    platform: "Tram",
                    isCancelled: true
                )
            ]
        ].mapValues { departures in
            departures.map { departure in
                departure.resolved(at: now)
            }
        }
    }

    private static func sampleDeparture(
        id: String,
        stopId: String,
        routeId: String,
        lineName: String,
        destination: String,
        minutesFromNow: Int,
        delayMinutes: Int? = 0,
        platform: String,
        isCancelled: Bool = false
    ) -> TimedFixtureDeparture {
        TimedFixtureDeparture(
            id: id,
            stopId: stopId,
            routeId: routeId,
            lineName: lineName,
            destination: destination,
            minutesFromNow: minutesFromNow,
            delayMinutes: delayMinutes,
            platform: platform,
            isCancelled: isCancelled
        )
    }

    private struct TimedFixtureDeparture {
        let id: String
        let stopId: String
        let routeId: String
        let lineName: String
        let destination: String
        let minutesFromNow: Int
        let delayMinutes: Int?
        let platform: String
        let isCancelled: Bool

        func resolved(at now: Date) -> Departure {
            let scheduled = now.addingTimeInterval(TimeInterval(minutesFromNow * 60))
            let realtime = scheduled.addingTimeInterval(TimeInterval((delayMinutes ?? 0) * 60))
            return Departure(
                id: id,
                stopId: stopId,
                routeId: routeId,
                lineName: lineName,
                destination: destination,
                scheduledDeparture: scheduled,
                realtimeDeparture: realtime,
                delayMinutes: delayMinutes,
                platform: platform,
                isCancelled: isCancelled,
                dataSource: .mock,
                lastUpdated: now
            )
        }
    }
}

struct FailingAVLClient: AVLClient {
    nonisolated func fetchMessages() async throws -> [AlertMessage] {
        throw AVLClientError.invalidResponse
    }
}

struct EmptyAVLClient: AVLClient {
    nonisolated func fetchMessages() async throws -> [AlertMessage] {
        []
    }
}

struct SevereMockAVLClient: AVLClient {
    nonisolated func fetchMessages() async throws -> [AlertMessage] {
        [
            AlertMessage(
                id: "severe-1",
                title: "Major disruption on T1 and line 4",
                body: "Luxembourg city centre services are severely disrupted. Expect cancellations and long transfer delays.",
                severity: .severe,
                affectedStopIds: ["sample-hamilius"],
                affectedRouteIds: ["4", "T1"],
                startsAt: .now,
                endsAt: nil,
                dataSource: .mock
            )
        ]
    }
}
