import SwiftUI
import UIKit
import UIOnboarding

/// SwiftUI adapter for UIOnboarding's UIKit welcome screen.
struct OnboardingView: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIOnboardingViewController

    let onGetStarted: () -> Void

    func makeUIViewController(context: Context) -> UIOnboardingViewController {
        let onboardingController = UIOnboardingViewController(
            withConfiguration: VerkeierOnboardingConfiguration.make()
        )
        onboardingController.delegate = context.coordinator
        return onboardingController
    }

    func updateUIViewController(
        _ uiViewController: UIOnboardingViewController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onGetStarted: onGetStarted)
    }

    final class Coordinator: NSObject, UIOnboardingViewControllerDelegate {
        private let onGetStarted: () -> Void

        init(onGetStarted: @escaping () -> Void) {
            self.onGetStarted = onGetStarted
        }

        func didFinishOnboarding(onboardingViewController: UIOnboardingViewController) {
            onGetStarted()
        }
    }
}

private enum VerkeierOnboardingConfiguration {
    static func make() -> UIOnboardingViewConfiguration {
        UIOnboardingViewConfiguration(
            appIcon: appIcon,
            firstTitleLine: titleLine("Welcome to", color: .label),
            secondTitleLine: titleLine("Verkéier", color: .systemRed),
            features: [
                UIOnboardingFeature(
                    icon: symbol("location.fill"),
                    iconTint: .systemRed,
                    title: "Find nearby stops",
                    description: "See public transport stops around you or search anywhere in Luxembourg."
                ),
                UIOnboardingFeature(
                    icon: symbol("arrow.triangle.swap"),
                    iconTint: .systemRed,
                    title: "Plan your journey",
                    description: "Compare routes and choose the way that suits you best."
                ),
                UIOnboardingFeature(
                    icon: symbol("clock.fill"),
                    iconTint: .systemRed,
                    title: "Know when to leave",
                    description: "Check upcoming departures, live updates, and service disruptions."
                )
            ],
            textViewConfiguration: UIOnboardingTextViewConfiguration(
                icon: symbol("location.circle"),
                text: "Location is optional. You can search for stops without sharing your location."
            ),
            buttonConfiguration: UIOnboardingButtonConfiguration(
                title: "Get started",
                backgroundColor: .systemRed
            )
        )
    }

    private static var appIcon: UIImage {
        UIImage(named: "Icon") ?? symbol("tram.fill")
    }

    private static func symbol(_ name: String) -> UIImage {
        UIImage(systemName: name) ?? UIImage(systemName: "circle.fill")!
    }

    private static func titleLine(_ text: String, color: UIColor) -> NSMutableAttributedString {
        NSMutableAttributedString(
            string: text,
            attributes: [.foregroundColor: color]
        )
    }
}

#Preview {
    OnboardingView(onGetStarted: {})
}
