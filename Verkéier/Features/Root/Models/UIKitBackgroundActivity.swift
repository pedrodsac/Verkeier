import UIKit

@MainActor
final class UIKitBackgroundActivity: BackgroundActivityAsserting {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    func begin() {
        guard identifier == .invalid else { return }
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Route preparation") { [weak self] in
            // Only release the assertion; the run itself is never cancelled.
            Task { @MainActor in self?.end() }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
