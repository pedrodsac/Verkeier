import CoreSpotlight
import Foundation
import Testing
@testable import Verkeier

@Suite("Launch optimisation model", .serialized)
@MainActor
struct RootModelTests {
    private func model(_ requirement: RoutingOptimisationRequirement, onboardingCompleted: Bool = true,
                       delay: Duration = .zero, background: any BackgroundActivityAsserting = NoBackgroundActivity(),
                       store: TransitIntentHandoffStore? = nil) -> RootModel {
        RootModel(initialRequirement: requirement, onboardingCompleted: onboardingCompleted,
                                presentationDelay: delay, background: background,
                                handoffStore: store ?? TransitIntentHandoffStore(defaults: UserDefaults(suiteName: "LaunchModelTests-\(UUID())")!))
    }

    private func settle(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() {
            try #require(ContinuousClock.now < deadline, "condition never became true")
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("When nothing is needed the map shows at once")
    func notNeeded() async {
        let model = model(.notNeeded)
        #expect(model.presentation() == .map)
        await model.run(using: UnavailableRoutingOptimisationService())
        #expect(model.presentation() == .map)
        #expect(model.phase == .idle)
    }

    @Test("A launch run shows the placeholder, then progress, then the map")
    func launchRun() async throws {
        let service = ScriptedService()
        let model = model(.needsFull, delay: .milliseconds(150))
        #expect(model.presentation() == .placeholder)
        let running = Task { await model.run(using: service) }
        try await service.waitUntilStarted()
        service.emit(.init(phase: .calculating, fraction: 0.4))
        try await settle { model.phase == .optimising(.init(phase: .calculating, fraction: 0.4)) }
        #expect(model.presentation() == .placeholder)
        try await settle { model.delayElapsed }
        #expect(model.presentation() == .optimisation(.init(phase: .calculating, fraction: 0.4)))
        service.finish()
        await running.value
        #expect(model.presentation() == .map)
    }

    @Test("A late progress report never moves the bar backwards")
    func progressIsMonotonic() async throws {
        let service = ScriptedService()
        let model = model(.needsIncremental)
        let running = Task { await model.run(using: service) }
        try await service.waitUntilStarted()
        service.emit(.init(phase: .calculating, fraction: 0.6))
        try await settle { model.phase == .optimising(.init(phase: .calculating, fraction: 0.6)) }
        service.emit(.init(phase: .calculating, fraction: 0.3))
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.phase == .optimising(.init(phase: .calculating, fraction: 0.6)))
        service.finish()
        await running.value
    }

    @Test("Onboarding is never interrupted and a run that ends meanwhile is never seen")
    func onboardingIsRespected() async throws {
        let service = ScriptedService()
        let model = model(.waitingForTimetable, onboardingCompleted: false)
        let running = Task { await model.run(using: service) }
        try await service.waitUntilWaiting()
        #expect(model.presentation() == .map)
        service.timetableArrives()
        try await service.waitUntilStarted()
        service.emit(.init(phase: .calculating, fraction: 0.5))
        try await settle { model.phase == .optimising(.init(phase: .calculating, fraction: 0.5)) }
        #expect(model.presentation() == .map)
        service.finish()
        await running.value
        model.onboardingDidFinish()
        #expect(model.presentation() == .map)
    }

    @Test("After onboarding ends the screen appears immediately for a first-run optimisation")
    func firstRunAfterOnboarding() async throws {
        let service = ScriptedService()
        let model = model(.waitingForTimetable, onboardingCompleted: false, delay: .seconds(60))
        let running = Task { await model.run(using: service) }
        try await service.waitUntilWaiting()
        service.timetableArrives()
        try await service.waitUntilStarted()
        service.emit(.init(phase: .calculating, fraction: 0.2))
        try await settle { model.phase == .optimising(.init(phase: .calculating, fraction: 0.2)) }
        model.onboardingDidFinish()
        #expect(model.presentation() == .optimisation(.init(phase: .calculating, fraction: 0.2)))
        service.finish()
        await running.value
        #expect(model.presentation() == .map)
    }

    @Test("A failure shows the failure screen once and then lets the user continue")
    func failure() async throws {
        let service = ScriptedService()
        let model = model(.needsFull)
        let running = Task { await model.run(using: service) }
        try await service.waitUntilStarted()
        service.finish(throwing: RoutingOptimisationError.stalled)
        await running.value
        #expect(model.presentation() == .failure)
        model.dismissFailure()
        #expect(model.presentation() == .map)
    }

    @Test("A failure behind onboarding is silent")
    func failureBehindOnboarding() async throws {
        let service = ScriptedService()
        let model = model(.waitingForTimetable, onboardingCompleted: false)
        let running = Task { await model.run(using: service) }
        try await service.waitUntilWaiting()
        service.timetableArrives()
        try await service.waitUntilStarted()
        service.finish(throwing: RoutingOptimisationError.stalled)
        await running.value
        #expect(model.presentation() == .map)
    }

    @Test("Cancellation ends quietly")
    func cancellation() async throws {
        let service = ScriptedService()
        let model = model(.needsFull)
        let running = Task { await model.run(using: service) }
        try await service.waitUntilStarted()
        service.finish(throwing: CancellationError())
        await running.value
        #expect(model.phase == .idle)
    }

    @Test("A run only ever starts once")
    func runsOnce() async throws {
        let service = ScriptedService()
        let model = model(.needsFull)
        let first = Task { await model.run(using: service) }
        try await service.waitUntilStarted()
        let second = Task { await model.run(using: service) }
        await second.value
        #expect(service.startCount == 1)
        service.finish()
        await first.value
    }

    @Test("The background assertion is held for the whole run")
    func backgroundAssertion() async throws {
        let background = RecordingBackground()
        let service = ScriptedService()
        let model = model(.needsFull, background: background)
        let running = Task { await model.run(using: service) }
        try await service.waitUntilStarted()
        #expect(background.events == ["begin"])
        service.finish()
        await running.value
        #expect(background.events == ["begin", "end"])
    }

    @Test("Links that arrive while the map is not mounted are stored for it")
    func linksAreForwarded() {
        let defaults = UserDefaults(suiteName: "LaunchModelLinks-\(UUID())")!
        let store = TransitIntentHandoffStore(defaults: defaults)
        let model = model(.needsFull, store: store)
        model.forward(TransitDeepLink.openStop(id: "stop-1").url)
        #expect(TransitIntentHandoff.consumePending(from: store) == .openFavouriteStop(stopId: "stop-1"))
        model.forward(TransitDeepLink.planRoute(destinationName: "Kirchberg").url)
        #expect(TransitIntentHandoff.consumePending(from: store) == .planRoute(destinationName: "Kirchberg"))
        model.forward(URL(string: "https://example.com")!)
        #expect(TransitIntentHandoff.consumePending(from: store) == nil)

        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: "stop.abc"]
        model.forwardSpotlight(activity)
        #expect(TransitIntentHandoff.consumePending(from: store) == .openFavouriteStop(stopId: "abc"))
        activity.userInfo = [CSSearchableItemActivityIdentifier: "other.abc"]
        model.forwardSpotlight(activity)
        #expect(TransitIntentHandoff.consumePending(from: store) == nil)
    }
}

// MARK: Support

@MainActor
private final class RecordingBackground: BackgroundActivityAsserting {
    private(set) var events: [String] = []
    func begin() { events.append("begin") }
    func end() { events.append("end") }
}

/// A service the test drives by hand.
private final class ScriptedService: RoutingOptimisationService, @unchecked Sendable {
    private let lock = NSLock()
    private var progress: (@Sendable (RoutingOptimisationProgress) -> Void)?
    private var finishRun: CheckedContinuation<Void, Error>?
    private var timetableContinuation: CheckedContinuation<Void, Never>?
    private var started = 0
    private var waiting = false

    var startCount: Int { lock.withLock { started } }

    func requirement() async -> RoutingOptimisationRequirement { .needsFull }

    func waitForTimetable() async {
        await withCheckedContinuation { continuation in
            lock.withLock { timetableContinuation = continuation; waiting = true }
        }
    }

    func optimise(progress: @escaping @Sendable (RoutingOptimisationProgress) -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock { self.progress = progress; finishRun = continuation; started += 1 }
        }
    }

    func emit(_ value: RoutingOptimisationProgress) { lock.withLock { progress }?(value) }

    func finish(throwing error: (any Error)? = nil) {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            defer { finishRun = nil }
            return finishRun
        }
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
    }

    func timetableArrives() { lock.withLock { () -> CheckedContinuation<Void, Never>? in defer { timetableContinuation = nil }; return timetableContinuation }?.resume() }

    func waitUntilStarted() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while startCount == 0 {
            try #require(ContinuousClock.now < deadline, "the run never started")
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    func waitUntilWaiting() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !lock.withLock({ waiting }) {
            try #require(ContinuousClock.now < deadline, "never waited for the timetable")
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
