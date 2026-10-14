import Foundation
import Valhalla

/// Decides which walking failures are safe to store as "no route".
///
/// Only failures that are a pure function of the two endpoints and the graph
/// qualify. Anything else (cancellation, a missing dataset, router or config
/// creation errors, wrapper failures with code -1) aborts a build instead, so a
/// transient problem can never become a permanent missing transfer.
nonisolated enum TransferWalkErrorClassifier {
    /// Valhalla input and path codes that depend only on the request:
    /// 154 path distance limit, 170 unconnected regions, 171 no suitable edges,
    /// 441 unreachable location, 442 no path found.
    static let deterministicValhallaCodes: Set<Int> = [154, 170, 171, 441, 442]

    static func isDeterministic(_ error: Error) -> Bool {
        switch error {
        case let error as WalkingRoutingError:
            return error == .noRoute || error == .invalidResponse
        case is DecodingError:
            return true
        case let error as ValhallaError:
            if case .valhallaError(let code, _) = error { return deterministicValhallaCodes.contains(code) }
            return false
        default:
            return false
        }
    }
}
