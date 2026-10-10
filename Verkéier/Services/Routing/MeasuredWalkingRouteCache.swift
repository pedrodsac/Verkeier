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
    private struct Flight {
        let id: UUID
        let task: Task<OfflineWalkingRoute, Error>
        var waiters: Set<UUID>
    }
    private var entries: [Key: Entry] = [:]
    private var flights: [Key: Flight] = [:]
    private var access: UInt64 = 0
    private let capacity = 512

    func route(from: LocationPoint, to: LocationPoint, revision: String,
               calculate: @escaping @Sendable () async throws -> OfflineWalkingRoute) async throws -> OfflineWalkingRoute {
        try Task.checkCancellation()
        let key = Key(fromLatitude: from.latitude, fromLongitude: from.longitude,
            toLatitude: to.latitude, toLongitude: to.longitude, revision: revision)
        access &+= 1
        if let cached = entries[key] {
            entries[key] = Entry(route: cached.route, access: access)
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
                if entries.count > capacity, let oldest = entries.min(by: { $0.value.access < $1.value.access })?.key {
                    entries[oldest] = nil
                }
            }
            return result
        } onCancel: {
            Task { await self.release(waiter, key: key, id: id) }
        }
    }
    private func release(_ waiter: UUID, key: Key, id: UUID) {
        guard var flight = flights[key], flight.id == id else { return }
        flight.waiters.remove(waiter)
        if flight.waiters.isEmpty { flight.task.cancel(); flights[key] = nil }
        else { flights[key] = flight }
    }
}
