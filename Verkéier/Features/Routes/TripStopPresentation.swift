import Foundation

nonisolated struct TripStopRowModel: Identifiable, Equatable {
    enum StatusTint { case green, orange, red, secondary }
    let id: Int
    let name: String
    let platform: String?
    let scheduledTime: Date?
    let liveTime: Date?
    let status: String
    let accessibilityStatus: String
    let statusTint: StatusTint
    let isPassed: Bool
    let isInRide: Bool
}

nonisolated enum TripStopPresentation {
    static let maximumAge: TimeInterval = 120

    static func rows(snapshot: TripDetailSnapshot, selection: TripDetailSelection,
        now: Date, refreshFailed: Bool) -> [TripStopRowModel] {
        func fresh(_ timing: TripStopTiming) -> Bool {
            timing.observedAt.map { now.timeIntervalSince($0) <= maximumAge && $0 <= now.addingTimeInterval(60) } ?? false
        }
        let passedSequence: Int? = snapshot.isCancelled ? nil : snapshot.stops.enumerated().compactMap { index, entry in
            // Arrival at an intermediate stop does not mean the bus has left it.
            let timing = index == snapshot.stops.count - 1 ? entry.arrival ?? entry.departure : entry.departure
            guard let timing, !timing.isCancelled else { return nil }
            if let time = timing.realtime {
                guard time <= now, timing.isHistoricalReport || (!refreshFailed && fresh(timing)) else { return nil }
            } else {
                // Without a live report, use the timetable to track progress.
                guard timing.scheduled <= now else { return nil }
            }
            return entry.sequence
        }.max()
        return snapshot.stops.enumerated().map { index, entry in
            let timing = index == snapshot.stops.count - 1 ? entry.arrival ?? entry.departure : entry.departure ?? entry.arrival
            let cancelled = snapshot.isCancelled || timing?.isCancelled == true
            let isStale = refreshFailed || timing.map { !$0.isHistoricalReport && !fresh($0) } == true
            let status: String
            let accessibilityStatus: String
            let tint: TripStopRowModel.StatusTint
            let minutes = timing.flatMap { timing in
                timing.realtime.map { minuteDelay(from: timing.scheduled, to: $0) }
            }
            if cancelled {
                status = "Cancelled"
                accessibilityStatus = status
                tint = isStale ? .secondary : .red
            } else if let minutes {
                let delay = minutes == 0 ? "On time" : minutes > 0 ? "+\(minutes)" : "\(minutes)"
                status = "\(delay)\(isStale ? " · Stale" : "")"
                let unit = abs(minutes) == 1 ? "minute" : "minutes"
                let spoken = minutes == 0 ? "On time" : minutes > 0 ? "\(minutes) \(unit) late" : "\(-minutes) \(unit) early"
                accessibilityStatus = "\(spoken)\(isStale ? ", stale" : "")"
                tint = isStale ? .secondary : minutes == 0 ? .green : .orange
            } else {
                status = "Live time unavailable"
                accessibilityStatus = status
                tint = .secondary
            }
            return TripStopRowModel(id: entry.sequence, name: entry.stop.fullName, platform: entry.platform,
                scheduledTime: timing?.scheduled, liveTime: minutes == 0 ? nil : timing?.realtime,
                status: status, accessibilityStatus: accessibilityStatus, statusTint: tint,
                isPassed: passedSequence.map { entry.sequence <= $0 } ?? false,
                isInRide: selection.boardingSequence...selection.alightingSequence ~= entry.sequence)
        }
    }

    /// Match the minute precision of the displayed clock times. GTFS can
    /// include seconds while ATP reports the start of the same minute.
    private static func minuteDelay(from scheduled: Date, to live: Date) -> Int {
        Int(floor(live.timeIntervalSince1970 / 60) - floor(scheduled.timeIntervalSince1970 / 60))
    }
}
