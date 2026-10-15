import SwiftUI

/// Full-screen, non-dismissable progress while stored transfer walks are prepared.
struct RoutePreparationScreen: View {
    enum State: Equatable {
        case working(RoutingOptimisationProgress)
        case failed
    }

    let state: State
    var onContinue: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var content: some View {
        VStack(spacing: 20) {
            Image(systemName: isFailed ? "exclamationmark.triangle" : "figure.walk.motion")
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.pulse, isActive: !isFailed && !reduceMotion)
                .foregroundStyle(isFailed ? Color.orange : Color.accentColor)
                .accessibilityHidden(true)
            Text(isFailed ? "Route preparation didn't finish" : "Getting routes ready")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            // The progress sits directly under the title so it stays on screen at
            // the largest accessibility text sizes, where the text below scrolls.
            if case .working(let progress) = state { progressView(progress) }
            Text(
                isFailed
                    ? "Route planning still works, but may be slower. Verkéier will try again the next time you open it."
                    : "Verkéier is measuring the walks between nearby stops so it can plan journeys faster. This only happens after a map or timetable update."
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            switch state {
            case .working:
                Text("Keep Verkéier open until this finishes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .failed:
                Button("Continue", action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: 520)
        .padding(32)
    }

    private func progressView(_ progress: RoutingOptimisationProgress) -> some View {
        ProgressView(value: progress.fraction) {
            Text(phaseTitle(progress.phase))
        } currentValueLabel: {
            Text(progress.fraction, format: .percent.precision(.fractionLength(0)))
        }
        .progressViewStyle(.linear)
        .animation(reduceMotion ? nil : .linear(duration: 0.2), value: progress.fraction)
        .accessibilityLabel("Route preparation progress")
        .accessibilityValue(Text(progress.fraction, format: .percent.precision(.fractionLength(0))))
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func phaseTitle(_ phase: RoutingOptimisationProgress.Phase) -> LocalizedStringKey {
        switch phase {
        case .preparing: "Preparing…"
        case .calculating: "Measuring walks between stops…"
        case .saving: "Saving…"
        }
    }

    private var isFailed: Bool { state == .failed }
}

#Preview("Preparing") {
    RoutePreparationScreen(state: .working(.init(phase: .preparing, fraction: 0.08)))
}

#Preview("Measuring, dark") {
    RoutePreparationScreen(state: .working(.init(phase: .calculating, fraction: 0.42)))
        .preferredColorScheme(.dark)
}

#Preview("Accessibility size") {
    RoutePreparationScreen(state: .working(.init(phase: .calculating, fraction: 0.42)))
        .dynamicTypeSize(.accessibility3)
}

#Preview("Failed") {
    RoutePreparationScreen(state: .failed)
}
