import Testing

@testable import Verkeier

struct StopDeduplicationTests {
    @Test func keepsBusAndTramStopsWhoseDisplayNamesMatch() {
        let busStop = makeStop(id: "bus", name: "Central (Bus)", mode: .bus)
        let tramStop = makeStop(id: "tram", name: "Central (Tram)", mode: .tram)

        let result = [busStop, tramStop].deduplicatedByExactName()

        #expect(busStop.displayName == tramStop.displayName)
        #expect(result.map(\.id) == ["bus", "tram"])
    }

    @Test func stillDeduplicatesStopsWithTheSameNameAndMode() {
        let first = makeStop(id: "first", name: "Central (Bus)", mode: .bus)
        let duplicate = makeStop(id: "duplicate", name: "Central (Bus)", mode: .bus)

        let result = [first, duplicate].deduplicatedByExactName()

        #expect(result.map(\.id) == ["first"])
    }

    private func makeStop(
        id: String,
        name: String,
        mode: TransportMode
    ) -> Stop {
        Stop(
            id: id,
            name: name,
            location: LocationPoint(latitude: 49.61, longitude: 6.13),
            modes: [mode],
            dataSource: .mock
        )
    }
}
