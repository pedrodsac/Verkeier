import SwiftUI

/// The Home tab's root: search results while searching, the dashboard otherwise.
struct BottomSheetContent: View {
    let isSearchActive: Bool
    let contentTopPadding: CGFloat

    var body: some View {
        if isSearchActive {
            SearchResultsContent()
        } else {
            CommuteDashboardView()
                .contentMargins(.top, contentTopPadding, for: .scrollContent)
        }
    }
}
