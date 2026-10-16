#if targetEnvironment(simulator) || ROUTING_BENCHMARK
import Foundation
import MobiliteitKit

/// JSON records for the benchmark's `samples.json`. Keys keep the names of earlier baselines.
nonisolated enum BenchmarkDiagnosticsExport {
    /// Every `RoutingRoundMetrics` field.
    static func round(_ round: RoutingRoundMetrics) -> [String: Any] {
        [
            "scan_ms": round.patternScanMilliseconds, "merge_ms": round.labelMergeMilliseconds,
            "prepare_ms": round.tripPreparationMilliseconds, "alights": round.alightingChecks,
            "retained": round.retainedLabels, "patterns": round.patterns,
            "trip_instances": round.tripInstances, "boarding_checks": round.boardingChecks,
            "feasible_boardings": round.feasibleBoardings, "label_attempts": round.labelAttempts,
            "rejected_before_allocation": round.rejectedBeforeAllocation,
            "slowest_chunk_ms": round.slowestChunkMilliseconds,
            "summed_chunk_ms": round.summedChunkMilliseconds,
        ]
    }

    /// An authoritative pass keeps its round count; a warm-up pass also lists its rounds,
    /// because its rounds are not part of `rounds`.
    static func pass(_ pass: RoutingDiagnostics.SearchPass, includingRounds: Bool = false) -> [String: Any] {
        var record: [String: Any] = [
            "start_ms": pass.startMilliseconds, "duration_ms": pass.durationMilliseconds,
            "horizon_s": pass.horizonSeconds, "wave": pass.realtimeWave, "rounds": pass.rounds.count,
            "candidates": pass.candidates, "walking_ms": pass.walkingMilliseconds,
        ]
        if includingRounds { record["round_metrics"] = pass.rounds.map(round) }
        return record
    }

    /// Per-stop arrival and matching times, relative to the operation start.
    static func boards(_ boards: [RoutingDiagnostics.BoardTiming]) -> [[String: Any]] {
        boards.map { board in
            var record: [String: Any] = ["stop": board.stopID]
            if let value = board.arrivedMilliseconds { record["arrived_ms"] = value }
            if let value = board.matchingStartedMilliseconds { record["matching_start_ms"] = value }
            if let value = board.matchingFinishedMilliseconds { record["matching_end_ms"] = value }
            return record
        }
    }
}
#endif
