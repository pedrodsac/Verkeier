import Foundation

/// What launch has to do about the stored transfer walks.
nonisolated enum RoutingOptimisationRequirement: Equatable, Sendable {
    case notNeeded
    /// No stored walks exist for the walking graph that is (or is about to be) active.
    case needsFull
    /// Walks exist for this graph, but for another timetable: only new pairs need computing.
    case needsIncremental
    /// The very first optimisation, before any timetable has been installed.
    case waitingForTimetable

    var needsWork: Bool { self == .needsFull || self == .needsIncremental }
}

nonisolated struct RoutingOptimisationProgress: Equatable, Sendable {
    enum Phase: Equatable, Sendable { case preparing, calculating, saving }
    var phase: Phase
    /// 0...1 across the whole run.
    var fraction: Double

    static let start = RoutingOptimisationProgress(phase: .preparing, fraction: 0)
}

nonisolated enum RoutingOptimisationError: Error, Equatable {
    case timetableUnavailable
    /// The build made no progress for too long and was stopped.
    case stalled
}

nonisolated protocol RoutingOptimisationService: Sendable {
    /// Re-evaluates the requirement after the bundled walking graph has finished installing.
    func requirement() async -> RoutingOptimisationRequirement
    /// Returns once a usable timetable is installed (or the caller is cancelled).
    func waitForTimetable() async
    /// Runs the optimisation. A second caller joins the run in flight and observes its progress.
    func optimise(progress: @escaping @Sendable (RoutingOptimisationProgress) -> Void) async throws
}

/// Default for previews and contexts that must never optimise (tests, benchmarks).
nonisolated struct UnavailableRoutingOptimisationService: RoutingOptimisationService {
    func requirement() async -> RoutingOptimisationRequirement { .notNeeded }
    func waitForTimetable() async {}
    func optimise(progress: @escaping @Sendable (RoutingOptimisationProgress) -> Void) async throws {}
}

/// Scripted service for previews and tests.
nonisolated struct FixtureRoutingOptimisationService: RoutingOptimisationService {
    var requirementValue: RoutingOptimisationRequirement = .needsFull
    var steps: [RoutingOptimisationProgress] = [
        .init(phase: .preparing, fraction: 0.05), .init(phase: .calculating, fraction: 0.4),
        .init(phase: .calculating, fraction: 0.8), .init(phase: .saving, fraction: 0.98)
    ]
    var stepDelay: Duration = .milliseconds(10)
    var timetableDelay: Duration = .milliseconds(10)
    var failure: (any Error)?

    func requirement() async -> RoutingOptimisationRequirement { requirementValue }

    func waitForTimetable() async { try? await Task.sleep(for: timetableDelay) }

    func optimise(progress: @escaping @Sendable (RoutingOptimisationProgress) -> Void) async throws {
        progress(.start)
        for step in steps {
            try await Task.sleep(for: stepDelay)
            progress(step)
        }
        if let failure { throw failure }
        progress(.init(phase: .saving, fraction: 1))
    }
}
