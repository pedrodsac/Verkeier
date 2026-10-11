import Foundation
import Testing
import Valhalla
import ValhallaConfigModels
import ValhallaModels
@testable import Verkeier

struct WalkingPathResponseTests {
    @Test(arguments: ["kilometers", "miles"])
    func decodesPathWithoutManeuvers(units: String) throws {
        let json = #"{"trip":{"status":0,"summary":{"length":0.1,"time":20},"units":"\#(units)","legs":[{"shape":"??_c`|@_c`|@"}]}}"#
        let route = try WalkingPathResponse.route(from: Data(json.utf8))
        #expect(route.duration == 20)
        #expect(abs(route.distanceMeters - (units == "kilometers" ? 100 : 160.9344)) < 0.00001)
        #expect(route.coordinates.count == 2)
        #expect(route.source == .localOSM)
    }

    @Test func rejectsFailureAndMissingPath() {
        for (status, shape) in [(1, "??_c`|@_c`|@"), (0, "??")] {
            let json = #"{"trip":{"status":\#(status),"summary":{"length":0.1,"time":20},"units":"kilometers","legs":[{"shape":"\#(shape)"}]}}"#
            #expect(throws: (any Error).self) { try WalkingPathResponse.route(from: Data(json.utf8)) }
        }
    }

    @Test(arguments: [0, 50])
    func omittingInstructionsAndDefaultFieldsPreservesNativePathAndTiming(reachability: Int) throws {
        let archive = try #require(Bundle.main.url(forResource: "luxembourg-walking-tiles", withExtension: "tar"))
        let config = try ValhallaConfig(tileExtractTar: archive)
        let engine = try Valhalla(config, configName: "walking-directions-tests.json")
        defer { engine.close() }
        let originalRequest = RouteRequest(locations: [RoutingWaypoint(lat: 49.6116, lon: 6.1319, minimumReachability: reachability),
            RoutingWaypoint(lat: 49.6120, lon: 6.1325, minimumReachability: reachability)], costing: .pedestrian, units: .km,
            directionsType: .instructions, shapeFormat: .polyline6)
        let original = try engine.route(request: originalRequest)
        let request = WalkingPathRequest.make(from: .init(latitude: 49.6116, longitude: 6.1319),
            to: .init(latitude: 49.6120, longitude: 6.1325), minimumReachability: reachability)
        let encoded = try JSONEncoder().encode(request)
        #expect(String(decoding: encoded, as: UTF8.self).contains("\"directions_type\":\"none\""))
        let raw = try engine.route(rawRequest: String(decoding: encoded, as: UTF8.self))
        let measured = try WalkingPathResponse.route(from: Data(raw.utf8))
        #expect(measured.duration == original.trip.summary.time)
        #expect(measured.distanceMeters == original.trip.summary.length * 1_000)
        #expect(measured.coordinates == (try original.trip.legs.flatMap { try ValhallaWalkingRouter.decodePolyline6($0.shape) }))
    }
}
