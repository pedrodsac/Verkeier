import BackgroundTasks
import Foundation

/// Keeps the local GTFS feed reasonably fresh without user action by running a
/// best-effort update from a `BGAppRefreshTask`. The OS schedules the work
/// opportunistically; we just request it and re-arm after each run.
enum GTFSBackgroundRefresh {
    static let identifier = "dev.pedrocordeiro.LuxTransit.gtfsRefresh"

    /// Request the next opportunistic refresh (no sooner than ~6h out).
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Run a best-effort GTFS update; downloads only when the remote feed changed.
    static func run() async {
        _ = await GTFSUpdateService().checkForUpdates(force: false)
    }
}
