import Foundation
import Testing

@testable import Verkeier

struct ATPMapperTests {
    @Test func mapsNearbyStopsPayload() throws {
        let response: ATPNearbyStopsResponse = try decode(
            """
            {
              "stopLocationOrCoordLocation": [
                {
                  "StopLocation": {
                    "id": "A=1@O=Test City, Hill Lift@X=6127990@Y=49611130@U=82@L=test-stop-1@",
                    "extId": "test-stop-1",
                    "name": "Test City, Hill Lift",
                    "lon": 6.12799,
                    "lat": 49.61113,
                    "productAtStop": [
                      { "name": "Funicular", "line": "F1", "catOutL": "Funicular" }
                    ]
                  }
                }
              ]
            }
            """,
            as: ATPNearbyStopsResponse.self
        )
        let stops = ATPMapper.mapNearbyStops(response)

        #expect(stops.count == 1)
        #expect(stops[0].id == "test-stop-1")
        #expect(stops[0].name == "Hill Lift")
        #expect(stops[0].locality == "Test City")
        #expect(stops[0].modes == [.funicular])
        #expect(stops[0].platformIds == ["test-stop-1"])
    }

    @Test func groupsNearbyPlatformStopsByStationName() throws {
        let response: ATPNearbyStopsResponse = try decode(
            """
            {
              "stopLocationOrCoordLocation": [
                {
                  "StopLocation": {
                    "id": "A=1@O=Centre, Badanstalt@L=300362002@",
                    "extId": "300362002",
                    "name": "Centre, Badanstalt",
                    "lon": 6.129043,
                    "lat": 49.613543,
                    "productAtStop": [
                      { "name": "Bus", "catOutL": "Bus" },
                      { "name": "Citybus", "catOutL": "Citybus" }
                    ]
                  }
                },
                {
                  "StopLocation": {
                    "id": "A=1@O=Centre, Badanstalt@L=300362001@",
                    "extId": "300362001",
                    "name": "Centre, Badanstalt",
                    "lon": 6.129331,
                    "lat": 49.613525,
                    "productAtStop": [
                      { "name": "Bus", "catOutL": "Bus" }
                    ]
                  }
                },
                {
                  "StopLocation": {
                    "id": "A=1@O=Hamilius-Centre (Tram)@L=300029001@",
                    "extId": "300029001",
                    "name": "Hamilius-Centre (Tram)",
                    "lon": 6.126104,
                    "lat": 49.611026,
                    "productAtStop": [
                      { "name": "Tram", "catOutL": "Tram" }
                    ]
                  }
                }
              ]
            }
            """,
            as: ATPNearbyStopsResponse.self
        )

        let stops = ATPMapper.mapNearbyStops(response)
        let badanstalt = try #require(stops.first { $0.name == "Badanstalt" })

        #expect(stops.count == 2)
        #expect(badanstalt.id == "300362001")
        #expect(badanstalt.locality == "Centre")
        #expect(badanstalt.platformIds == ["300362001", "300362002"])
        #expect(badanstalt.modes == [.bus])
    }

    @Test func mapsDepartureBoardPayloadWithDelayStatus() throws {
        let response: ATPDepartureBoardResponse = try decode(
            """
            {
              "Departure": [
                {
                  "name": "Funicular F1",
                  "type": "ST",
                  "stop": "Test City, Hill Lift",
                  "stopid": "test-stop-1",
                  "stopExtId": "test-stop-1",
                  "time": "10:00:00",
                  "date": "2026-06-13",
                  "rtTime": "10:05:00",
                  "rtDate": "2026-06-13",
                  "direction": "Upper Station",
                  "platform": "1",
                  "cancelled": false,
                  "Product": {
                    "name": "Funicular F1",
                    "line": "F1",
                    "catOutL": "Funicular",
                    "operator": "Test Operator"
                  }
                }
              ]
            }
            """,
            as: ATPDepartureBoardResponse.self
        )
        let departures = ATPMapper.mapDepartures(response, stopId: "test-stop-1")

        #expect(departures.count == 1)
        #expect(departures[0].lineName == "F1")
        #expect(departures[0].destination == "Upper Station")
        #expect(departures[0].delayMinutes == 5)
        #expect(departures[0].status == .delayed(minutes: 5))
    }

    @Test func mapsLiveDepartureBoardPayloadWithProductArrayAndPlatformObject() throws {
        let response: ATPDepartureBoardResponse = try decode(
            """
            {
              "Departure": [
                {
                  "name": "Bus 15",
                  "stop": "Centre, Badanstalt",
                  "stopid": "A=1@O=Centre, Badanstalt@X=6129043@Y=49613543@U=82@L=300362002@",
                  "stopExtId": "300362002",
                  "time": "13:38:00",
                  "date": "2026-06-15",
                  "rtTime": "13:41:00",
                  "rtDate": "2026-06-15",
                  "direction": "Hollerich, P+R Bouillon",
                  "platform": { "type": "ST", "text": "2" },
                  "Product": [
                    {
                      "name": "Bus 15",
                      "line": "15",
                      "catOutL": "Bus",
                      "operator": "Ville de Luxembourg - Service Autobus"
                    }
                  ]
                }
              ]
            }
            """,
            as: ATPDepartureBoardResponse.self
        )

        let departures = ATPMapper.mapDepartures(response, stopId: "300362001")

        #expect(departures.count == 1)
        #expect(departures[0].lineName == "15")
        #expect(departures[0].platform == "2")
        #expect(departures[0].operatorName == "Ville de Luxembourg - Service Autobus")
    }

    @Test func mapsRealtimePlatformWhenStaticPlatformIsMissing() throws {
        let response: ATPDepartureBoardResponse = try decode(
            """
            {
              "Departure": [
                {
                  "name": "Train RE 1",
                  "type": "ST",
                  "stopExtId": "gare-1",
                  "time": "14:00:00",
                  "date": "2026-06-15",
                  "rtTime": "14:01:00",
                  "rtDate": "2026-06-15",
                  "direction": "Ettelbruck",
                  "rtPlatform": { "type": "ST", "text": "4" },
                  "Product": {
                    "name": "Train RE 1",
                    "line": "RE 1",
                    "catOutL": "Train"
                  }
                }
              ]
            }
            """,
            as: ATPDepartureBoardResponse.self
        )

        let departure = try #require(ATPMapper.mapDepartures(response, stopId: "gare-1").first)

        #expect(departure.platform == "4")
        #expect(departure.previousPlatform == nil)
    }

    @Test func prefersRealtimePlatformAndKeepsStaticPlatformAsPreviousAssignment() throws {
        let response: ATPDepartureBoardResponse = try decode(
            """
            {
              "Departure": [
                {
                  "name": "Train RE 1",
                  "type": "ST",
                  "stopExtId": "gare-1",
                  "time": "14:00:00",
                  "date": "2026-06-15",
                  "direction": "Ettelbruck",
                  "platform": "2",
                  "rtPlatform": "4",
                  "Product": {
                    "name": "Train RE 1",
                    "line": "RE 1",
                    "catOutL": "Train"
                  }
                }
              ]
            }
            """,
            as: ATPDepartureBoardResponse.self
        )

        let departure = try #require(ATPMapper.mapDepartures(response, stopId: "gare-1").first)

        #expect(departure.platform == "4")
        #expect(departure.previousPlatform == "2")
        #expect(departure.hasPlatformChange)
    }

    @Test func mapsTrackFieldsWithRealtimeTrackTakingPrecedence() throws {
        let response: ATPDepartureBoardResponse = try decode(
            """
            {
              "Departure": [
                {
                  "name": "Train RE 1",
                  "stopExtId": "gare-1",
                  "time": "14:00:00",
                  "date": "2026-06-15",
                  "direction": "Ettelbruck",
                  "platform": { "type": "ST", "text": "1" },
                  "rtPlatform": { "type": "ST", "text": "3" },
                  "track": "2",
                  "rtTrack": "4",
                  "Product": { "line": "RE 1", "catOutL": "Train" }
                }
              ]
            }
            """,
            as: ATPDepartureBoardResponse.self
        )

        let departure = try #require(ATPMapper.mapDepartures(response, stopId: "gare-1").first)

        #expect(departure.platform == "4")
        #expect(departure.previousPlatform == "2")
        #expect(departure.hasPlatformChange)
    }

    @Test func mapsTrackWhenPlatformFieldsAreMissingAndIgnoresBlankTrack() throws {
        let response: ATPDepartureBoardResponse = try decode(
            """
            {
              "Departure": [
                {
                  "name": "Bus 1",
                  "stopExtId": "stop-1",
                  "time": "14:00:00",
                  "date": "2026-06-15",
                  "track": " 2 ",
                  "Product": { "line": "1", "catOutL": "Bus" }
                },
                {
                  "name": "Bus 2",
                  "stopExtId": "stop-1",
                  "time": "14:10:00",
                  "date": "2026-06-15",
                  "track": " ",
                  "platform": "3",
                  "Product": { "line": "2", "catOutL": "Bus" }
                },
                {
                  "name": "Bus 3",
                  "stopExtId": "stop-1",
                  "time": "14:20:00",
                  "date": "2026-06-15",
                  "rtTrack": "4",
                  "Product": { "line": "3", "catOutL": "Bus" }
                }
              ]
            }
            """,
            as: ATPDepartureBoardResponse.self
        )

        let departures = ATPMapper.mapDepartures(response, stopId: "stop-1")

        #expect(departures.map(\.platform) == ["2", "3", "4"])
    }

    @Test func infersOmittedPlatformsFromOtherDeparturesAtTheSamePhysicalStop() throws {
        let response: ATPDepartureBoardResponse = try decode(
            """
            {
              "Departure": [
                {
                  "name": "Bus 2",
                  "stopExtId": "300469001",
                  "time": "19:54:00",
                  "date": "2026-06-15",
                  "direction": "Bonnevoie, Lycée Bouneweg PE",
                  "platform": { "type": "ST", "text": "2" },
                  "Product": { "line": "2", "catOutL": "Bus" }
                },
                {
                  "name": "Bus 2",
                  "stopExtId": "300469001",
                  "time": "20:24:00",
                  "date": "2026-06-15",
                  "direction": "Bonnevoie, Lycée Bouneweg PE",
                  "Product": { "line": "2", "catOutL": "Bus" }
                },
                {
                  "name": "Bus 2",
                  "stopExtId": "300469002",
                  "time": "20:11:00",
                  "date": "2026-06-15",
                  "direction": "Limpertsberg, Lycée Michel Lucius",
                  "platform": "1",
                  "Product": { "line": "2", "catOutL": "Bus" }
                },
                {
                  "name": "Bus 2",
                  "stopExtId": "300469002",
                  "time": "20:41:00",
                  "date": "2026-06-15",
                  "direction": "Limpertsberg, Lycée Michel Lucius",
                  "Product": { "line": "2", "catOutL": "Bus" }
                }
              ]
            }
            """,
            as: ATPDepartureBoardResponse.self
        )

        let departures = ATPMapper.mapDepartures(response, stopId: "300469001")

        #expect(departures.map(\.platform) == ["2", "2", "1", "1"])
    }

    @Test func doesNotInferWhenOnePhysicalStopReportsMultiplePlatforms() throws {
        let response: ATPDepartureBoardResponse = try decode(
            """
            {
              "Departure": [
                {
                  "name": "Train RE 1",
                  "stopExtId": "gare-1",
                  "time": "14:00:00",
                  "date": "2026-06-15",
                  "direction": "Ettelbruck",
                  "platform": "2",
                  "Product": { "line": "RE 1", "catOutL": "Train" }
                },
                {
                  "name": "Train RE 2",
                  "stopExtId": "gare-1",
                  "time": "14:10:00",
                  "date": "2026-06-15",
                  "direction": "Liège",
                  "platform": "4",
                  "Product": { "line": "RE 2", "catOutL": "Train" }
                },
                {
                  "name": "Train RE 3",
                  "stopExtId": "gare-1",
                  "time": "14:20:00",
                  "date": "2026-06-15",
                  "direction": "Trier",
                  "Product": { "line": "RE 3", "catOutL": "Train" }
                }
              ]
            }
            """,
            as: ATPDepartureBoardResponse.self
        )

        let departures = ATPMapper.mapDepartures(response, stopId: "gare-1")

        #expect(departures[2].platform == nil)
    }

    @Test func doesNotInferWhenTrackAssignmentsConflict() throws {
        let response: ATPDepartureBoardResponse = try decode(
            """
            {
              "Departure": [
                {
                  "name": "Train RE 1",
                  "stopExtId": "gare-1",
                  "time": "14:00:00",
                  "date": "2026-06-15",
                  "track": "2",
                  "Product": { "line": "RE 1", "catOutL": "Train" }
                },
                {
                  "name": "Train RE 2",
                  "stopExtId": "gare-1",
                  "time": "14:10:00",
                  "date": "2026-06-15",
                  "track": "4",
                  "Product": { "line": "RE 2", "catOutL": "Train" }
                },
                {
                  "name": "Train RE 3",
                  "stopExtId": "gare-1",
                  "time": "14:20:00",
                  "date": "2026-06-15",
                  "Product": { "line": "RE 3", "catOutL": "Train" }
                }
              ]
            }
            """,
            as: ATPDepartureBoardResponse.self
        )

        let departures = ATPMapper.mapDepartures(response, stopId: "gare-1")

        #expect(departures[2].platform == nil)
    }

    @Test func mergedDeparturesDeduplicatesAndSortsBoards() {
        let now = Date(timeIntervalSince1970: 1_000)
        let duplicateWithoutRealtime = Departure(
            id: "duplicate-old",
            stopId: "platform-1",
            lineName: "15",
            destination: "Hollerich",
            scheduledDeparture: now.addingTimeInterval(120),
            realtimeDeparture: nil,
            platform: "1",
            dataSource: .atpOpenAPI
        )
        let duplicateWithRealtime = Departure(
            id: "duplicate-new",
            stopId: "platform-2",
            lineName: "15",
            destination: "Hollerich",
            scheduledDeparture: now.addingTimeInterval(120),
            realtimeDeparture: now.addingTimeInterval(180),
            platform: "1",
            dataSource: .atpOpenAPI
        )
        let earlier = Departure(
            id: "earlier",
            stopId: "platform-1",
            lineName: "10",
            destination: "Gare",
            scheduledDeparture: now.addingTimeInterval(60),
            dataSource: .atpOpenAPI
        )

        let departures = ATPMapper.mergedDepartures([
            duplicateWithoutRealtime,
            earlier,
            duplicateWithRealtime,
        ])

        #expect(departures.map(\.id) == ["earlier", "duplicate-new"])
    }

    private func decode<Value: Decodable>(_ json: String, as type: Value.Type) throws -> Value {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(Value.self, from: data)
    }
}
