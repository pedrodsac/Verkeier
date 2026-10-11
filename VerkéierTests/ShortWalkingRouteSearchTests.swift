import Foundation
import Testing
@testable import Verkeier

struct ShortWalkingRouteSearchTests {
    @Test func retainsMeasuredShortPath() async throws {
        let fixture = TransferSearchFixture()
        let route = try await ShortWalkingRouteSearch.route { try await fixture.calculate($0) }
        #expect(route == fixture.short)
        #expect(await fixture.probes == [0])
    }

    @Test(arguments: [0, 1, 2])
    func retriesFullCorrelationForFailureOrUnusableTransfer(caseIndex: Int) async throws {
        let fixture = TransferSearchFixture(failureCase: caseIndex)
        let route = try await ShortWalkingRouteSearch.route { try await fixture.calculate($0) }
        #expect(route == fixture.short)
        #expect(await fixture.probes == [0, 50])
    }

    @Test func cancellationDoesNotStartFullRetry() async {
        let fixture = TransferSearchFixture(failureCase: 3)
        do {
            _ = try await ShortWalkingRouteSearch.route { try await fixture.calculate($0) }
            Issue.record("Cancellation was swallowed")
        } catch is CancellationError { }
        catch { Issue.record("Unexpected error: \(error)") }
        #expect(await fixture.probes == [0])
    }
}

private actor TransferSearchFixture {
    nonisolated let short = OfflineWalkingRoute(distanceMeters: 100, duration: 60,
        coordinates: [.init(latitude: 49.6, longitude: 6.1), .init(latitude: 49.601, longitude: 6.1)],
        source: .localOSM)
    let failureCase: Int?
    var probes: [Int] = []
    init(failureCase: Int? = nil) { self.failureCase = failureCase }
    func calculate(_ reach: Int) throws -> OfflineWalkingRoute {
        probes.append(reach)
        if reach == 0 {
            switch failureCase {
            case 0: throw WalkingRoutingError.noRoute
            case 1: return .init(distanceMeters: 2_000, duration: 60, coordinates: [], source: .localOSM)
            case 2: return .init(distanceMeters: 100, duration: 750, coordinates: [], source: .localOSM)
            case 3: throw CancellationError()
            default: break
            }
        }
        return short
    }
}
