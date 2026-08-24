import Testing

@testable import Verkeier

@MainActor
struct TransitSheetNavigationStateTests {
    @Test func tabOrderMatchesThePersistentBottomSheetContract() {
        #expect(TransitSheetTab.allCases == [.home, .favourites, .plan, .settings])
    }

    @Test func tabsAndPathsStayIndependent() {
        let navigation = TransitSheetNavigationState()
        let stop = Stop(
            id: "stop-1",
            name: "Hamilius",
            location: LocationPoint(latitude: 49.611, longitude: 6.126),
            modes: [.bus],
            dataSource: .gtfs
        )

        navigation.homePath = [.search]
        navigation.favouritesPath = [.stopDetail(stop)]
        navigation.planPath = [.routeTimeline("route-1")]

        navigation.selectedTab = .home
        #expect(navigation.activePath == [.search])
        navigation.selectedTab = .favourites
        #expect(navigation.activePath == [.stopDetail(stop)])
        navigation.selectedTab = .plan
        #expect(navigation.activePath == [.routeTimeline("route-1")])
        navigation.selectedTab = .settings
        #expect(navigation.activePath.isEmpty)
        #expect(navigation.homePath == [.search])
    }

    @Test func planEndpointSearchIsPushedOntoPlanPath() {
        let navigation = TransitSheetNavigationState()

        navigation.selectedTab = .plan
        navigation.planPath.append(.routePlaceSearch(.destination))

        #expect(navigation.activePath == [.routePlaceSearch(.destination)])
    }
}
