import Foundation

/// Whole-minute presentation only; route calculations retain precise durations.
nonisolated enum DurationDisplay {
    static func minutes(_ seconds: TimeInterval, rounding: FloatingPointRoundingRule) -> Int? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        let minutes = (seconds / 60).rounded(rounding)
        guard minutes > 0, minutes < Double(Int.max) else { return nil }
        return Int(minutes)
    }
}
