import Foundation

/// Shares measured paths across transit, refinement and bike-share callers.
/// A directed coordinate key includes the immutable graph revision.
actor MeasuredWalkingRouteCache {
    private struct Key: Hashable, Sendable {
        let fromLatitude: Double; let fromLongitude: Double
        let toLatitude: Double; let toLongitude: Double
        let revision: String
    }
    private struct Entry { let route: OfflineWalkingRoute; let access: UInt64 }
    private struct Access { let key: Key; let generation: UInt64 }
    private struct Flight {
        let id: UUID
        let task: Task<OfflineWalkingRoute, Error>
        var waiters: Set<UUID>
    }
    private var entries: [Key: Entry] = [:]
    private var flights: [Key: Flight] = [:]
    private var access: UInt64 = 0
    private var accesses: [Access] = []
    private var accessCursor = 0
    private let capacity: Int

    init(capacity: Int = 8_192) {
        self.capacity = max(1, capacity)
    }

    func route(
        from: LocationPoint,
        to: LocationPoint,
        revision: String,
        calculate: @escaping @Sendable () async throws -> OfflineWalkingRoute
    ) async throws -> OfflineWalkingRoute {
        try Task.checkCancellation()
        let key = Key(
            fromLatitude: from.latitude,
            fromLongitude: from.longitude,
            toLatitude: to.latitude,
            toLongitude: to.longitude,
            revision: revision
        )
        access &+= 1
        if let cached = entries[key] {
            entries[key] = Entry(route: cached.route, access: access)
            recordAccess(key)
            return cached.route
        }
        let waiter = UUID()
        var flight = flights[key] ?? Flight(id: UUID(), task: Task { try await calculate() }, waiters: [])
        flight.waiters.insert(waiter); flights[key] = flight
        let id = flight.id, task = flight.task
        return try await withTaskCancellationHandler {
            defer { release(waiter, key: key, id: id) }
            let result = try await task.value
            try Task.checkCancellation()
            if flights[key]?.id == id {
                access &+= 1; entries[key] = Entry(route: result, access: access)
                recordAccess(key)
                while entries.count > capacity {
                    let oldest = accesses[accessCursor]
                    accessCursor += 1
                    if entries[oldest.key]?.access == oldest.generation {
                        entries[oldest.key] = nil
                    }
                }
            }
            return result
        } onCancel: {
            Task { await self.release(waiter, key: key, id: id) }
        }
    }
    private func recordAccess(_ key: Key) {
        accesses.append(.init(key: key, generation: access))
        // Bound bookkeeping on hits as well as insertions. Each live entry has
        // one current record; obsolete records can be discarded in one pass.
        if accesses.count >= capacity * 4 {
            accesses = accesses[accessCursor...].filter {
                entries[$0.key]?.access == $0.generation
            }
            accessCursor = 0
        }
    }
    private func release(_ waiter: UUID, key: Key, id: UUID) {
        guard var flight = flights[key], flight.id == id else { return }
        flight.waiters.remove(waiter)
        if flight.waiters.isEmpty { flight.task.cancel(); flights[key] = nil } else { flights[key] = flight }
    }
}
