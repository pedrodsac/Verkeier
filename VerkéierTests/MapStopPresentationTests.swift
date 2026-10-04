import Testing
@testable import Verkeier

@MainActor
struct MapStopPresentationTests {
    @Test func suppressesSameIDRegardlessOfNameAndDistance() {
        let model = TransitMapViewModel()
        model.nearbyStops = [stop("same", "Live name", latitude: 49.60)]
        model.gtfsMapStops = [stop("same", "Static name", latitude: 49.70)]
        #expect(model.gtfsOnlyMapStops.isEmpty)
    }

    @Test func matchesNormalizedNamesOnlyWhenClose() {
        let model = TransitMapViewModel()
        model.nearbyStops = [stop("live", " École Centrale ", latitude: 49.60)]
        model.gtfsMapStops = [
            stop("close", "ecole centrale", latitude: 49.6005),
            stop("distant", "ecole centrale", latitude: 49.70),
            stop("different", "Gare", latitude: 49.60)
        ]
        #expect(model.gtfsOnlyMapStops.map(\.id) == ["distant", "different"])
    }

    @Test func checksEveryNearbyCandidateWithTheSameName() {
        let model = TransitMapViewModel()
        model.nearbyStops = [
            stop("distant", "Central", latitude: 49.70),
            stop("close", "Central", latitude: 49.60)
        ]
        model.gtfsMapStops = [stop("static", "Central", latitude: 49.6005)]
        #expect(model.gtfsOnlyMapStops.isEmpty)
    }

    @Test func refreshesDerivedStopsWhenEitherSourceChanges() {
        let model = TransitMapViewModel()
        let staticStop = stop("static", "Central", latitude: 49.60)
        model.gtfsMapStops = [staticStop]
        #expect(model.gtfsOnlyMapStops == [staticStop])
        model.nearbyStops = [stop("live", "Central", latitude: 49.60)]
        #expect(model.gtfsOnlyMapStops.isEmpty)
        model.nearbyStops = []
        #expect(model.gtfsOnlyMapStops == [staticStop])
        model.gtfsMapStops = []
        #expect(model.gtfsOnlyMapStops.isEmpty)
    }

    private func stop(_ id: String, _ name: String, latitude: Double) -> Stop {
        Stop(id: id, name: name,
             location: LocationPoint(latitude: latitude, longitude: 6.13),
             modes: [.bus], dataSource: .mock)
    }
}
