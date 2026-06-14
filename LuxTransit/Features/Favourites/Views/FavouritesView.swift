import SwiftUI

struct FavouritesView: View {
    let favourites: [Stop]
    let selectStop: (Stop) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if favourites.isEmpty {
                ContentUnavailableView(
                    "No favourites",
                    systemImage: "star",
                    description: Text("Save a stop from its detail view.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(favourites) { stop in
                            StopListRow(stop: stop, markerColor: .yellow) {
                                selectStop(stop)
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    FavouritesView(favourites: [], selectStop: { _ in })
}
