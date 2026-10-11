import Foundation

/// Keeps each result at its request index, including failures and cancellation.
nonisolated enum WalkingRouteBatch {
    static func resolve(
        _ requests: [OfflineWalkingRequest], maximumConcurrency: Int,
        calculate: @escaping @Sendable (OfflineWalkingRequest) async throws -> OfflineWalkingRoute
    ) async -> [OfflineWalkingRoute?] {
        guard !requests.isEmpty else { return [] }
        var results = Array<OfflineWalkingRoute?>(repeating: nil, count: requests.count)
        guard !Task.isCancelled else { return results }
        return await withTaskGroup(of: (Int, OfflineWalkingRoute?).self) { group in
            var next = 0
            func add(_ index: Int) -> Bool {
                group.addTaskUnlessCancelled {
                    guard !Task.isCancelled else { return (index, nil) }
                    return (index, try? await calculate(requests[index]))
                }
            }
            for _ in 0..<min(max(1, maximumConcurrency), requests.count) {
                guard add(next) else { break }
                next += 1
            }
            while let (index, value) = await group.next() {
                if !Task.isCancelled { results[index] = value }
                if next < requests.count, !Task.isCancelled {
                    guard add(next) else { break }
                    next += 1
                }
            }
            return results
        }
    }
}
