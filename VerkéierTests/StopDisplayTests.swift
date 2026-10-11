import Foundation
import Testing
@testable import Verkeier

@MainActor
struct StopDisplayTests {
    @Test(arguments: [[TransportMode.train], [.train, .bus], [.bus], [.tram], []])
    func swapsLocalityOnlyForTrainStations(modes: [TransportMode]) throws {
        let stop = makeStop(name: "Lorentzweiler, Gare", modes: modes)
        let isTrain = modes.contains(.train)
        #expect(stop.displayName == (isTrain ? "Lorentzweiler" : "Gare"))
        #expect(stop.displaySubtitle == (isTrain ? "Gare" : "Lorentzweiler"))
        #expect(stop.name == "Lorentzweiler, Gare")
        #expect(stop.fullName == "Lorentzweiler, Gare")
        #expect(stop.locality == "Lorentzweiler")

        let place = RoutePlace(stop: stop, source: .search)
        #expect(place.title == stop.displayName)
        #expect(place.subtitle == stop.displaySubtitle)

        let decoded = try JSONDecoder().decode(Stop.self, from: JSONEncoder().encode(stop))
        #expect(decoded.displayName == stop.displayName)
        #expect(decoded.displaySubtitle == stop.displaySubtitle)
    }

    @Test func usesSeparatelyProvidedLocalityForTrainStations() {
        let stop = makeStop(name: "Gare", locality: " Lorentzweiler ", modes: [.train])
        #expect(stop.displayName == "Lorentzweiler")
        #expect(stop.displaySubtitle == "Gare")
        #expect(stop.fullName == "Lorentzweiler, Gare")
    }

    @Test func preservesTrainStationNameWithoutLocality() {
        let stop = makeStop(name: "Lorentzweiler", modes: [.train])
        #expect(stop.displayName == "Lorentzweiler")
        #expect(stop.displaySubtitle == nil)
    }

    private func makeStop(name: String, locality: String? = nil, modes: [TransportMode]) -> Stop {
        Stop(id: "station", name: name, locality: locality,
             location: LocationPoint(latitude: 49.7, longitude: 6.14),
             modes: modes, dataSource: .mock)
    }
}
