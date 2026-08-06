import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct VerkéierWidgets: WidgetBundle {
    var body: some Widget {
        FavouriteStopWidget()
        DeparturesSummaryWidget()
        DepartureCountdownActivityWidget()
    }
}
