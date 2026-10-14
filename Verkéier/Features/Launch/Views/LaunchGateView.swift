import CoreSpotlight
import SwiftUI

/// Root of the app: shows the map, or the blocking route preparation screen
/// while stored transfer walks are built after a map or timetable update.
struct LaunchGateView: View {
    let locationService: LocationService
    let model: LaunchOptimisationModel

    @Environment(\.routingOptimisationService) private var optimisationService

    var body: some View {
        // The container keeps one identity, so swapping the content never restarts the task.
        Group {
            switch model.presentation() {
            case .map:
                TransitMapScreen(locationService: locationService)
                    .environment(\.launchOnboardingDidFinish, { model.onboardingDidFinish() })
            case .placeholder:
                placeholder.handlingLinks(model)
            case .optimisation(let progress):
                RoutingOptimisationScreen(state: .working(progress)).handlingLinks(model)
            case .failure:
                RoutingOptimisationScreen(state: .failed, onContinue: { model.dismissFailure() }).handlingLinks(model)
            }
        }
        .task { await model.run(using: optimisationService) }
    }

    /// The launch screen's icon on the system background. The storyboard lays the
    /// icon out at 200 pt on a 414 pt screen and scales it with the width.
    private var placeholder: some View {
        GeometryReader { proxy in
            Color(.systemBackground)
                .overlay {
                    Image("Icon").resizable().scaledToFit()
                        .frame(width: 200 * proxy.size.width / 414, height: 200 * proxy.size.width / 414)
                        .accessibilityHidden(true)
                }
        }
        .ignoresSafeArea()
    }
}

private extension View {
    /// While the map is not mounted, store incoming links for it to replay.
    func handlingLinks(_ model: LaunchOptimisationModel) -> some View {
        onOpenURL { model.forward($0) }
            .onContinueUserActivity(CSSearchableItemActionType) { model.forwardSpotlight($0) }
    }
}

#Preview("Preparing") {
    LaunchGateView(locationService: LocationService(),
                   model: LaunchOptimisationModel(initialRequirement: .needsFull, onboardingCompleted: true,
                                                  presentationDelay: .zero))
        .environment(\.routingOptimisationService, FixtureRoutingOptimisationService(stepDelay: .seconds(1)))
}
