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

    @Test func stationNamesMatchWithoutLocalityPrefix() {
        #expect("Luxembourg, Gare Centrale".identifiesSameStation(as: "Gare Centrale"))
    }

    @Test func stationNamesMatchIgnoringFeedQualifiersAndDiacritics() {
        #expect("Kirchberg, Luxexpo (Tram)".identifiesSameStation(as: "LUXEXPO"))
    }

    @Test func differentStationsDoNotMatch() {
        #expect(!"Luxembourg, Gare Centrale".identifiesSameStation(as: "Hamilius"))
    }

    @Test func blankDirectionDoesNotMatchAStop() {
        #expect(!"".identifiesSameStation(as: "Luxembourg, Gare Centrale"))
    }
}
