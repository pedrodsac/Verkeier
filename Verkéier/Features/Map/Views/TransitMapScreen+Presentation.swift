import SwiftUI

extension TransitMapScreen {
    static let regularWidthPresentationDetent = PresentationDetent.fraction(1)

    var sheetPresentationDetent: Binding<PresentationDetent> {
        Binding(
            get: {
                // Regular width (iPad) only supports a single detent, so the
                // selection must match it or UIKit throws.
                sizeClass == .compact ? router.detent.presentationDetent : Self.regularWidthPresentationDetent
            },
            set: { presentationDetent in
                guard sizeClass == .compact else { return }
                router.detent = BottomSheetDetent(presentationDetent: presentationDetent)
            }
        )
    }
}
