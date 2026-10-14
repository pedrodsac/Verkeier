import Foundation

/// Remembers optimisation attempts that did not finish, so a build that crashes
/// or fails every time cannot block every launch. Also remembers a bundled
/// walking graph whose installation failed, so the launch check stops expecting it.
nonisolated struct RoutingOptimisationAttemptLedger: Sendable {
    static let attemptLimit = 2
    private static let attemptsKey = "RoutingOptimisation.attempts"
    private static let failedInstallKey = "RoutingOptimisation.failedBundledInstall"

    // UserDefaults is documented as thread-safe.
    private nonisolated(unsafe) let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func attempts(for target: String) -> Int {
        (defaults.dictionary(forKey: Self.attemptsKey) as? [String: Int])?[target] ?? 0
    }

    func isBlocked(target: String) -> Bool { attempts(for: target) >= Self.attemptLimit }

    /// Only the current target is kept; older targets are pruned.
    func recordStart(for target: String) {
        defaults.set([target: attempts(for: target) + 1], forKey: Self.attemptsKey)
    }

    func recordFinish(for target: String) {
        defaults.removeObject(forKey: Self.attemptsKey)
    }

    /// A plain cancellation is not the build's fault and does not count.
    func recordAbandoned(for target: String) {
        let remaining = attempts(for: target) - 1
        if remaining > 0 { defaults.set([target: remaining], forKey: Self.attemptsKey) }
        else { defaults.removeObject(forKey: Self.attemptsKey) }
    }

    var failedBundledInstall: String? { defaults.string(forKey: Self.failedInstallKey) }

    func recordBundledInstall(_ state: RoutingDataState, identity: String?) {
        switch state {
        case .failed: if let identity { defaults.set(identity, forKey: Self.failedInstallKey) }
        case .ready: defaults.removeObject(forKey: Self.failedInstallKey)
        default: break
        }
    }
}
