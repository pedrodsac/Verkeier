import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct LuxTransitWidgets: WidgetBundle {
    var body: some Widget {
        FavouriteStopWidget()
        DeparturesSummaryWidget()
        DepartureCountdownActivityWidget()
    }
}
