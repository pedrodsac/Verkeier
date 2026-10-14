import CoreSpotlight
import Foundation
import Observation

/// Holds the background-task assertion while the optimisation runs. The expiry
/// handler only releases the assertion: the run is never cancelled, so iOS may
/// suspend it and it resumes in the foreground.
@MainActor
protocol BackgroundActivityAsserting {
    func begin()
    func end()
}

nonisolated struct NoBackgroundActivity: BackgroundActivityAsserting {
    func begin() {}
    func end() {}
}

/// Decides what the launch gate shows while stored transfer walks are prepared.
@Observable @MainActor
final class LaunchOptimisationModel {
    enum Phase: Equatable {
        case idle
        /// The very first optimisation, before a timetable exists. The map stays usable.
        case waitingForTimetable
        case optimising(RoutingOptimisationProgress)
        case failed
    }

    enum Presentation: Equatable {
        /// Matches the launch screen, so a run that is over almost at once never flashes.
        case placeholder
        case map
        case optimisation(RoutingOptimisationProgress)
        case failure
    }

    private(set) var phase: Phase
    private(set) var delayElapsed = false
    private(set) var onboardingDismissed: Bool
    /// True when the run was already needed at launch, rather than after the first timetable install.
    let isLaunchRun: Bool

    private let initialRequirement: RoutingOptimisationRequirement
    private let presentationDelay: Duration
    private let background: any BackgroundActivityAsserting
    private let handoffStore: TransitIntentHandoffStore
    private var didStart = false
    private var delayTask: Task<Void, Never>?

    init(initialRequirement: RoutingOptimisationRequirement, onboardingCompleted: Bool,
         presentationDelay: Duration = .milliseconds(400),
         background: any BackgroundActivityAsserting = NoBackgroundActivity(),
         handoffStore: TransitIntentHandoffStore = .shared) {
        self.initialRequirement = initialRequirement
        self.onboardingDismissed = onboardingCompleted
        self.presentationDelay = presentationDelay
        self.background = background
        self.handoffStore = handoffStore
        isLaunchRun = initialRequirement.needsWork
        switch initialRequirement {
        case .notNeeded: phase = .idle
        case .waitingForTimetable: phase = .waitingForTimetable
        case .needsFull, .needsIncremental: phase = .optimising(.start)
        }
        if isLaunchRun { startDelay() }
    }

    // MARK: Presentation

    func presentation() -> Presentation {
        switch phase {
        case .idle, .waitingForTimetable:
            return .map
        case .optimising(let progress):
            // Never interrupt onboarding. A run that finishes meanwhile is never seen.
            guard onboardingDismissed else { return .map }
            return delayElapsed || !isLaunchRun ? .optimisation(progress) : .placeholder
        case .failed:
            return onboardingDismissed ? .failure : .map
        }
    }

    /// Sent when the onboarding cover has finished dismissing, never earlier,
    /// so the map is not torn down in the middle of its own dismissal.
    func onboardingDidFinish() { onboardingDismissed = true }

    func dismissFailure() { phase = .idle }

    // MARK: Run

    func run(using service: any RoutingOptimisationService) async {
        guard !didStart else { return }
        didStart = true
        switch initialRequirement {
        case .notNeeded:
            phase = .idle
        case .needsFull, .needsIncremental:
            await optimise(using: service)
        case .waitingForTimetable:
            phase = .waitingForTimetable
            await service.waitForTimetable()
            guard !Task.isCancelled else { return }
            await optimise(using: service)
        }
    }

    private func optimise(using service: any RoutingOptimisationService) async {
        phase = .optimising(.start)
        startDelay()
        background.begin()
        defer { background.end() }
        do {
            try await service.optimise { [weak self] progress in
                Task { @MainActor in self?.apply(progress) }
            }
            phase = .idle
        } catch is CancellationError {
            // Retried on the next launch.
            phase = .idle
        } catch {
            phase = .failed
        }
    }

    private func apply(_ progress: RoutingOptimisationProgress) {
        // Progress callbacks hop threads; a late one must never move the bar backwards.
        guard case .optimising(let current) = phase, progress.fraction >= current.fraction else { return }
        phase = .optimising(progress)
    }

    private func startDelay() {
        delayTask?.cancel()
        delayElapsed = false
        let delay = presentationDelay
        delayTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.delayElapsed = true
        }
    }

    // MARK: Links that arrive while the map is not mounted

    /// Stores the link as an intent handoff, which the map replays when it appears.
    func forward(_ url: URL) {
        guard let deepLink = TransitDeepLink(url: url), let handoff = TransitIntentHandoff(deepLink) else { return }
        TransitIntentHandoff.save(handoff, store: handoffStore)
    }

    func forwardSpotlight(_ activity: NSUserActivity) {
        guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              identifier.hasPrefix("stop.") else { return }
        TransitIntentHandoff.save(.openFavouriteStop(stopId: String(identifier.dropFirst("stop.".count))), store: handoffStore)
    }
}
