import Foundation
import Observation

@Observable @MainActor
final class TripDetailViewModel {
    private(set) var selection: TripDetailSelection?
    private(set) var snapshot: TripDetailSnapshot?
    private(set) var rows: [TripStopRowModel] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var refreshFailed = false
    private var generation = 0
    private var refreshRevision = 0
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = { .now }) { self.now = now }

    func select(_ selection: TripDetailSelection) {
        guard self.selection != selection else { return }
        generation += 1
        self.selection = selection
        snapshot = nil
        rows = []
        errorMessage = nil
        refreshFailed = false
        isLoading = false
    }

    func deactivate() {
        generation += 1
        isLoading = false
    }

    func observe(_ selection: TripDetailSelection, using service: any TripDetailService) async {
        select(selection)
        let expected = generation
        await refresh(using: service, policy: .useCache)
        var ticks = 0
        while !Task.isCancelled, expected == generation {
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard !Task.isCancelled, expected == generation else { return }
            updateProgress()
            ticks += 1
            if ticks.isMultiple(of: 3) { await refresh(using: service, policy: .forceRefresh) }
        }
    }

    func refresh(using service: any TripDetailService, policy: RouteRealtimeRefreshPolicy = .forceRefresh) async {
        guard let selection else { return }
        let expected = generation
        refreshRevision += 1
        let revision = refreshRevision
        isLoading = true
        defer { if expected == generation, revision == refreshRevision { isLoading = false } }
        do {
            var loaded = try await service.tripDetail(for: selection, refreshPolicy: policy)
            guard !Task.isCancelled, expected == generation, revision == refreshRevision,
                  loaded.instance == selection.instance else { return }
            guard !loaded.stops.isEmpty else { throw TripDetailError.unavailable }
            if !loaded.liveDataAvailable, let snapshot {
                // A failed board fetch cannot erase useful live or historical evidence.
                loaded = TripDetailSnapshot(instance: loaded.instance, stops: snapshot.stops,
                    mapOverlay: loaded.mapOverlay, isApproximateRoute: loaded.isApproximateRoute,
                    liveDataAvailable: false, isCancelled: snapshot.isCancelled, fetchedAt: snapshot.fetchedAt)
            } else if let previous = snapshot {
                loaded = retainingHistoricalReports(in: loaded, from: previous)
            }
            snapshot = loaded
            refreshFailed = !loaded.liveDataAvailable
            errorMessage = loaded.liveDataAvailable ? nil : "Live data is unavailable. Showing the last available information."
            updateProgress()
        } catch is CancellationError { return }
        catch TripDetailError.obsoleteFeed {
            guard !Task.isCancelled, expected == generation, revision == refreshRevision else { return }
            snapshot = nil
            rows = []
            errorMessage = TripDetailError.obsoleteFeed.localizedDescription
        } catch {
            guard !Task.isCancelled, expected == generation, revision == refreshRevision else { return }
            refreshFailed = true
            errorMessage = snapshot == nil ? error.localizedDescription
                : "Live data could not be refreshed. Showing the last available information."
            updateProgress()
        }
    }

    func updateProgress() {
        guard let snapshot, let selection else { rows = []; return }
        rows = TripStopPresentation.rows(snapshot: snapshot, selection: selection,
            now: now(), refreshFailed: refreshFailed)
    }

    private func retainingHistoricalReports(in latest: TripDetailSnapshot,
        from previous: TripDetailSnapshot) -> TripDetailSnapshot {
        let old = Dictionary(uniqueKeysWithValues: previous.stops.map { ($0.sequence, $0) })
        let stops = latest.stops.map { entry in
            func retain(_ timing: TripStopTiming?, previous: TripStopTiming?) -> TripStopTiming? {
                guard timing?.realtime == nil, let previous, previous.isHistoricalReport,
                      let realtime = previous.realtime, realtime <= now() else { return timing }
                return previous
            }
            return TripStopEntry(sequence: entry.sequence, stop: entry.stop,
                arrival: retain(entry.arrival, previous: old[entry.sequence]?.arrival),
                departure: retain(entry.departure, previous: old[entry.sequence]?.departure), platform: entry.platform)
        }
        return TripDetailSnapshot(instance: latest.instance, stops: stops, mapOverlay: latest.mapOverlay,
            isApproximateRoute: latest.isApproximateRoute, liveDataAvailable: latest.liveDataAvailable,
            isCancelled: latest.isCancelled, fetchedAt: latest.fetchedAt)
    }
}
