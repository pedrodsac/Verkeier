import SwiftUI

struct FavouriteStopDepartureCard: View {
    let stop: Stop
    let selectStop: () -> Void

    var body: some View {
        StopListRow(
            stop: stop,
            markerColor: .blue,
            surface: .favourite,
            action: selectStop
        )
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    FavouriteStopDepartureCard(
        stop: Stop(
            id: "200209001",
            name: "Hamilius",
            locality: "Luxembourg",
            location: LocationPoint(latitude: 49.6107, longitude: 6.1268),
            modes: [.bus, .tram],
            dataSource: .mock
        ),
        selectStop: {}
    )
    .padding(.horizontal, 16)
}
