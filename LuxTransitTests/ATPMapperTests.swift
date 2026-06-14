import Foundation
import Testing

@testable import LuxTransit

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

    private func decode<Value: Decodable>(_ json: String, as type: Value.Type) throws -> Value {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(Value.self, from: data)
    }
}
