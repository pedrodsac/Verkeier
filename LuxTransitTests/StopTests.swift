import Foundation
import Testing

@testable import LuxTransit

struct StopTests {
    @Test func infersLocalityAndDisplayNameFromPrefixedFeedName() throws {
        let stop = try JSONDecoder().decode(
            Stop.self,
            from: Data(
                """
                {
                  "id": "tram-1",
                  "name": "Kirchberg, École européenne",
                  "locality": null,
                  "location": { "id": "tram-1", "latitude": 49.635, "longitude": 6.17 },
                  "modes": ["tram"],
                  "dataSource": "gtfs"
                }
                """.utf8
            )
        )

        #expect(stop.locality == "Kirchberg")
        #expect(stop.displayName == "École européenne")
    }

    @Test func keepsExplicitLocalityWhenItDiffersFromNamePrefix() {
        let stop = Stop(
            id: "coque",
            name: "Luxembourg, Coque",
            locality: "Kirchberg",
            location: LocationPoint(latitude: 49.6256, longitude: 6.1556),
            modes: [.tram],
            dataSource: .gtfs
        )

        #expect(stop.locality == "Kirchberg")
        #expect(stop.displayName == "Luxembourg, Coque")
    }

    @Test func infersLocalityFromQualifiedTramName() {
        let stop = Stop(
            id: "tram-2",
            name: "Hamilius-Centre (Tram)",
            location: LocationPoint(latitude: 49.6107, longitude: 6.1268),
            modes: [.tram],
            dataSource: .atpOpenAPI
        )

        #expect(stop.locality == "Centre")
        #expect(stop.name == "Hamilius-Centre")
    }
}
