import Foundation
import Testing

@testable import Verkeier

struct StationNameTests {
    @Test func removesAllFeedQualifiers() {
        #expect("Hamilius (Tram)".stationDisplayName == "Hamilius")
        #expect("Gare (Bus) (prov.)".stationDisplayName == "Gare")
        #expect("Centre (prov.) - Quai 1".stationDisplayName == "Centre - Quai 1")
    }

    @Test func normalizesStopAndLocationNames() {
        let stop = Stop(
            id: "stop",
            name: "Hamilius (Tram)",
            location: LocationPoint(
                id: "stop",
                name: "Hamilius (Tram)",
                latitude: 49.611,
                longitude: 6.126
            ),
            dataSource: .mock
        )

        #expect(stop.name == "Hamilius")
        #expect(stop.displayName == "Hamilius")
        #expect(stop.location.name == "Hamilius")
    }
}
