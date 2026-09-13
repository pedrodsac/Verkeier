import Foundation
import Testing
@testable import Verkeier

struct TransitServiceFixtureTests {
    @Test func parsesFractionalPublicCatalogueTimestamps() {
        let date = MobiliteitGTFSService.parseResourceDate("2026-09-10T05:19:16.095000+00:00")

        #expect(date != nil)
        #expect(date?.formatted(.iso8601.year().month().day()) == "2026-09-10")
    }

    @Test func resolvesAUniqueLiveStationOntoItsMatchingGTFSStop() async {
        let staticStop = stop(id: "gtfs-1", name: "Gare Centrale")
        let gtfs = FixtureGTFSService(stops: [staticStop])
        let live = FixtureLiveTransitService(nearbyResults: [
            LiveTransitStop(
                stationID: "hafas-9",
                externalID: nil,
                name: "Gare Centrale",
                location: staticStop.location,
                distanceMeters: 12,
                modes: [.train]
            )
        ])

        let resolved = await live.resolvedStop(for: staticStop, gtfsService: gtfs)

        #expect(resolved.gtfsStopID == "gtfs-1")
        #expect(resolved.hafasStationIDs == ["hafas-9"])
        #expect(resolved.dataSource == .gtfs)
    }

    @Test func rejectsAmbiguousLiveStationMatches() async {
        let staticStop = stop(id: "gtfs-1", name: "Gare Centrale")
        let gtfs = FixtureGTFSService(stops: [staticStop])
        let live = FixtureLiveTransitService(nearbyResults: [
            LiveTransitStop(stationID: "hafas-1", externalID: nil, name: "Gare Centrale", location: staticStop.location, distanceMeters: 12, modes: [.train]),
            LiveTransitStop(stationID: "hafas-2", externalID: nil, name: "Gare Centrale", location: staticStop.location, distanceMeters: 18, modes: [.train])
        ])

        let resolved = await live.resolvedStop(for: staticStop, gtfsService: gtfs)

        #expect(resolved.hafasStationIDs.isEmpty)
        #expect(resolved.id == "gtfs-1")
    }

    @Test func settingsDescribeReadyScheduleAndConfiguredLiveRelay() {
        let downloadedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let readiness = SettingsSupport.readinessSnapshot(
            configuration: AppConfiguration(
                apiProxyURL: URL(string: "https://relay.example")!,
                avlMessagesURL: URL(string: "https://avl.example/messages.xml")!
            ),
            gtfsStatus: GTFSFeedStatus(
                phase: .ready,
                resourceTitle: "gtfs-test.zip",
                downloadedAt: downloadedAt,
                lastCheckedAt: downloadedAt,
                validThrough: "2026-12-12",
                errorMessage: nil
            ),
            liveTransitLastUpdated: downloadedAt,
            liveTransitErrorMessage: nil
        )

        #expect(readiness.summaryTitle == "Transit data is ready")
        #expect(readiness.items.first(where: { $0.id == "gtfs" })?.status == "Ready")
        #expect(readiness.items.first(where: { $0.id == "atp" })?.status == "Available")
    }

    private func stop(id: String, name: String) -> Stop {
        Stop(
            id: id,
            name: name,
            location: LocationPoint(id: id, name: name, latitude: 49.6116, longitude: 6.1319),
            modes: [.train],
            dataSource: .gtfs,
            gtfsStopID: id
        )
    }
}
