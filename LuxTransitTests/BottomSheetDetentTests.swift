import SwiftUI
import Testing

@testable import LuxTransit

struct BottomSheetDetentTests {
    @Test func mapsAppDetentsToSystemPresentationDetents() {
        #expect(BottomSheetDetent.collapsed.presentationDetent == .height(132))
        #expect(BottomSheetDetent.medium.presentationDetent == .fraction(0.58))
        #expect(BottomSheetDetent.expanded.presentationDetent == .large)
    }

    @Test func mapsSystemPresentationDetentsBackToAppDetents() {
        #expect(BottomSheetDetent(presentationDetent: .height(132)) == .collapsed)
        #expect(BottomSheetDetent(presentationDetent: .fraction(0.58)) == .medium)
        #expect(BottomSheetDetent(presentationDetent: .large) == .expanded)
    }
}
