import SwiftUI

struct RouteView: View {
    let viewModel: RoutePresentationModel
    let calculateRoute: () -> Void
    let openInAppleMaps: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let selectedStop = viewModel.selectedStop {
                Text("To \(selectedStop.name)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Choose a stop from the map, favourites, nearby suggestions, or search.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(12)
                    .background(
                        .orange.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if let routePlan = viewModel.routePlan {
                RouteSummary(plan: routePlan)
            }

            HStack(spacing: 10) {
                Button(action: calculateRoute) {
                    Label(
                        viewModel.isCalculating ? "Calculating" : "Calculate",
                        systemImage: "point.topleft.down.curvedto.point.bottomright.up"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.selectedStop == nil || viewModel.isCalculating)

                Button(action: openInAppleMaps) {
                    Label("Apple Maps", systemImage: "map")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(viewModel.selectedStop == nil)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RouteSummary: View {
    let plan: RoutePlan

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let expectedTravelTime = plan.expectedTravelTime {
                Label(durationText(expectedTravelTime), systemImage: "clock")
            }
            if let distanceMeters = plan.distanceMeters {
                Label(distanceText(distanceMeters), systemImage: "road.lanes")
            }
            Text("Route provided by Apple Maps / MapKit.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let minutes = max(1, Int((duration / 60).rounded()))
        return "\(minutes) min"
    }

    private func distanceText(_ distance: Double) -> String {
        if distance >= 1000 {
            return String(format: "%.1f km", distance / 1000)
        }
        return "\(Int(distance)) m"
    }
}
