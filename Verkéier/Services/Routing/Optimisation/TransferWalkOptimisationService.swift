import Foundation
import MobiliteitKit
import OSLog

/// What the optimiser needs from the timetable service.
nonisolated protocol RoutingTimetableProviding: Sendable {
    func routingDatabaseURL() async -> URL?
    func refreshIfNeeded(force: Bool) async -> GTFSFeedStatus
}

extension MobiliteitGTFSService: RoutingTimetableProviding {}

/// Builds and installs the stored transfer walk table. One run at a time: a second
/// caller joins the run in flight. Every failure leaves the previous table untouched.
actor TransferWalkOptimisationService: RoutingOptimisationService {
    private let environment: RoutingOptimisationEnvironment
    private let computer: any TransferWalkComputing
    private let timetable: any RoutingTimetableProviding
    private let transferRequests: @Sendable (URL) async throws -> [WalkingRequest]
    private let graphInstall: Task<RoutingDataState, Never>?
    private let stallTimeout: Duration
    private let pollInterval: Duration
    private let logger = Logger(subsystem: "dev.pedrocordeiro.Verkeier", category: "TransferWalks")

    private var run: (id: UUID, task: Task<Void, Error>)?
    private var observers: [UUID: @Sendable (RoutingOptimisationProgress) -> Void] = [:]
    private var latest: RoutingOptimisationProgress?
    private var lastWholePercent = -1
    private var lastActivity = ContinuousClock.now
    private var watchdogArmed = false

    init(environment: RoutingOptimisationEnvironment, computer: any TransferWalkComputing,
         timetable: any RoutingTimetableProviding,
         transferRequests: @escaping @Sendable (URL) async throws -> [WalkingRequest],
         graphInstall: Task<RoutingDataState, Never>? = nil,
         stallTimeout: Duration = .seconds(60), pollInterval: Duration = .seconds(2)) {
        self.environment = environment
        self.computer = computer
        self.timetable = timetable
        self.transferRequests = transferRequests
        self.graphInstall = graphInstall
        self.stallTimeout = stallTimeout
        self.pollInterval = pollInterval
    }

    // MARK: RoutingOptimisationService

    func requirement() async -> RoutingOptimisationRequirement {
        await finishGraphInstall()
        return RoutingOptimisationLaunchCheck.requirement(in: environment)
    }

    func waitForTimetable() async {
        if await timetable.routingDatabaseURL() != nil { return }
        // Joins the refresh the map has already started, or starts it.
        _ = await timetable.refreshIfNeeded(force: false)
        while !Task.isCancelled {
            if await timetable.routingDatabaseURL() != nil { return }
            try? await Task.sleep(for: pollInterval)
        }
    }

    func optimise(progress: @escaping @Sendable (RoutingOptimisationProgress) -> Void) async throws {
        let id = UUID()
        observers[id] = progress
        if let latest { progress(latest) }
        let current: (id: UUID, task: Task<Void, Error>)
        if let run { current = run } else {
            latest = nil
            lastWholePercent = -1
            current = (UUID(), Task(priority: .utility) { [self] in try await self.runWithWatchdog() })
            run = current
        }
        defer { observers[id] = nil }
        try await withTaskCancellationHandler {
            do { try await current.task.value } catch {
                if run?.id == current.id { run = nil }
                throw error
            }
            if run?.id == current.id { run = nil }
        } onCancel: {
            // A departing observer never cancels the run for the others.
            Task { await self.removeObserver(id) }
        }
    }

    // MARK: Run

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
        if observers.isEmpty { run?.task.cancel() }
    }

    private func finishGraphInstall() async {
        guard let graphInstall else { return }
        let state = await graphInstall.value
        let bundled = RoutingOptimisationLaunchCheck.bundledManifest(in: environment)
        environment.ledger.recordBundledInstall(state, identity: bundled.map(RoutingOptimisationLaunchCheck.bundledInstallIdentity))
    }

    private func runWithWatchdog() async throws {
        lastActivity = .now
        watchdogArmed = false
        let work = Task(priority: .utility) { try await self.execute() }
        let timeout = stallTimeout
        let watchdog = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: timeout / 4)
                if await self.hasStalled() { work.cancel(); return }
            }
        }
        defer { watchdog.cancel() }
        do {
            try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
        } catch is CancellationError {
            if hasStalledFlag { throw RoutingOptimisationError.stalled }
            throw CancellationError()
        }
    }

    private var hasStalledFlag = false

    private func hasStalled() -> Bool {
        guard watchdogArmed, ContinuousClock.now - lastActivity > stallTimeout else { return false }
        hasStalledFlag = true
        return true
    }

    private func emit(_ phase: RoutingOptimisationProgress.Phase, _ fraction: Double) {
        lastActivity = .now
        let clamped = min(1, max(0, fraction))
        let whole = Int(clamped * 100)
        // The builder reports thousands of times; observers only need whole percents.
        guard whole != lastWholePercent || latest?.phase != phase || clamped == 1 else { return }
        lastWholePercent = whole
        let value = RoutingOptimisationProgress(phase: phase, fraction: max(clamped, latest?.fraction ?? 0))
        latest = value
        for observer in observers.values { observer(value) }
    }

    private func execute() async throws {
        hasStalledFlag = false
        emit(.preparing, 0)
        await finishGraphInstall()
        emit(.preparing, 0.03)

        var requirement = RoutingOptimisationLaunchCheck.requirement(in: environment)
        if requirement == .waitingForTimetable {
            await waitForTimetable()
            try Task.checkCancellation()
            requirement = RoutingOptimisationLaunchCheck.requirement(in: environment)
        }
        guard requirement.needsWork else {
            emit(.saving, 1)
            return
        }

        let dataset = try await computer.prepareTransferWalkComputation()
        emit(.preparing, 0.08)
        guard let databaseURL = await timetable.routingDatabaseURL() else { throw RoutingOptimisationError.timetableUnavailable }
        let timetableIdentity = databaseURL.lastPathComponent
        let requests = try await transferRequests(databaseURL)
        try Task.checkCancellation()
        emit(.preparing, 0.12)

        let graph = dataset.transferWalkIdentity.value
        let target = RoutingOptimisationLaunchCheck.target(graph: graph, timetable: timetableIdentity)
        environment.ledger.recordStart(for: target)
        do {
            var existing: TransferWalkTable?
            switch environment.store.load() {
            case .table(let table): existing = table
            case .invalid(let stamp): environment.store.discard(ifStillMatching: stamp)
            case .missing, .unreadable: break
            }
            watchdogArmed = true
            defer { watchdogArmed = false }
            let started = ContinuousClock.now
            let result = try await TransferWalkTableBuilder(computer: computer).build(
                requests: requests, dataset: dataset, reusing: existing, timetableIdentity: timetableIdentity
            ) { completed, total in
                Task { await self.reportBuild(completed: completed, total: total) }
            }
            emit(.saving, 0.97)
            try environment.store.write(result.data)
            guard case .table(let written) = environment.store.load() else { throw TransferWalkTableError.malformed("written table") }
            await computer.adoptTransferWalks(written)
            environment.ledger.recordFinish(for: target)
            emit(.saving, 1)
            logger.info("Transfer walks ready: \(result.pairs) pairs, \(result.reused) reused, \(result.computed) computed, \(result.negatives) without route, \(Int(RoutingDiagnostics.elapsed(since: started))) ms")
        } catch is CancellationError {
            // A stall counts as a failed attempt; any other cancellation does not.
            if !hasStalledFlag { environment.ledger.recordAbandoned(for: target) }
            throw CancellationError()
        }
    }

    private func reportBuild(completed: Int, total: Int) {
        // Late reports from the build must not move a finished run backwards.
        guard latest?.phase != .saving else { return }
        emit(.calculating, 0.12 + 0.85 * (total == 0 ? 1 : Double(completed) / Double(total)))
    }
}
