import Foundation
import MobiliteitKit

/// What the table builder needs from the walking router. The production
/// implementation is `LocalFirstWalkingRouter`; tests supply a fake.
nonisolated protocol TransferWalkComputing: Sendable {
    /// The active graph, with its first native router already open.
    func prepareTransferWalkComputation() async throws -> RoutingDataset
    /// Strict short-search computation: throws for anything but a deterministic failure.
    func transferWalkOutcome(from: LocationPoint, to: LocationPoint, dataset: RoutingDataset) async throws -> TransferWalkOutcome
    func isActiveDataset(_ dataset: RoutingDataset) async -> Bool
    /// Makes a freshly written table live for the running router.
    func adoptTransferWalks(_ table: TransferWalkTable) async
}

extension LocalFirstWalkingRouter: TransferWalkComputing {}

nonisolated struct TransferWalkBuildResult: Equatable, Sendable {
    let data: Data
    let pairs: Int
    let reused: Int
    let computed: Int
    let negatives: Int
}

nonisolated enum TransferWalkBuildError: Error, Equatable {
    /// The active walking graph changed while the table was being built.
    case graphChanged
    /// So many pairs had no route that the result is more likely a fault than a map.
    case implausibleNegatives(negatives: Int, pairs: Int)
}

/// Builds the stored table for a set of transfer requests, reusing every entry
/// of a table made for the same walking graph. Nothing is returned unless the
/// whole build succeeds, so a failure or cancellation never yields a partial table.
nonisolated struct TransferWalkTableBuilder: Sendable {
    let computer: any TransferWalkComputing
    /// Matches the router pool: four native Valhalla instances.
    var concurrency = 4

    init(computer: any TransferWalkComputing, concurrency: Int = 4) {
        self.computer = computer
        self.concurrency = max(1, concurrency)
    }

    @concurrent
    func build(requests: [WalkingRequest], dataset: RoutingDataset, reusing existing: TransferWalkTable?,
               timetableIdentity: String?,
               progress: @escaping @Sendable (_ completed: Int, _ total: Int) -> Void) async throws -> TransferWalkBuildResult {
        // Map exactly as the router's provider does, drop duplicates and Pafendall pairs.
        var pairsByKey: [TransferWalkKey: (from: LocationPoint, to: LocationPoint)] = [:]
        for request in requests {
            let from = LocalFirstWalkingRoutingProvider.walkingEndpoint(request.source)
            let to = LocalFirstWalkingRoutingProvider.walkingEndpoint(request.destination)
            guard PafendallFunicularConnection.terminals(from: from, to: to) == nil else { continue }
            pairsByKey[TransferWalkKey(from: from, to: to)] = (from, to)
        }
        let keys = pairsByKey.keys.sorted()

        let graph = dataset.transferWalkIdentity.value
        let reusable = existing.flatMap { $0.graphIdentity == graph ? $0 : nil }
        var payloads: [TransferWalkKey: Data] = [:]
        payloads.reserveCapacity(keys.count)
        var missing: [TransferWalkKey] = []
        for key in keys {
            if let payload = reusable?.payload(for: key) { payloads[key] = payload } else { missing.append(key) }
        }
        let reused = payloads.count
        let previousNegatives = reusable?.negativeCount() ?? 0

        progress(0, missing.count)
        var completed = 0
        if !missing.isEmpty {
            try await withThrowingTaskGroup(of: (TransferWalkKey, Data).self) { group in
                var next = 0
                func addNext() {
                    let key = missing[next]
                    let pair = pairsByKey[key]!
                    next += 1
                    group.addTask {
                        let outcome = try await computer.transferWalkOutcome(from: pair.from, to: pair.to, dataset: dataset)
                        return (key, try TransferWalkTableCodec.encodePayload(outcome))
                    }
                }
                for _ in 0..<min(concurrency, missing.count) { addNext() }
                while let (key, payload) = try await group.next() {
                    payloads[key] = payload
                    completed += 1
                    progress(completed, missing.count)
                    if next < missing.count { addNext() }
                }
            }
        }
        try Task.checkCancellation()

        let negatives = payloads.values.reduce(0) { $0 + ($1.first == 0 ? 1 : 0) }
        guard negatives <= max(2 * previousNegatives, keys.count / 4) else {
            throw TransferWalkBuildError.implausibleNegatives(negatives: negatives, pairs: keys.count)
        }
        guard await computer.isActiveDataset(dataset) else { throw TransferWalkBuildError.graphChanged }
        try Task.checkCancellation()

        let data = try TransferWalkTableCodec.encodeTable(
            graphIdentity: graph, timetableIdentity: timetableIdentity,
            entries: keys.map { (key: $0, payload: payloads[$0]!) })
        return TransferWalkBuildResult(data: data, pairs: keys.count, reused: reused, computed: missing.count, negatives: negatives)
    }
}
