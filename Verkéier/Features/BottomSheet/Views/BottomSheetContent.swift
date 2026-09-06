import SwiftUI

struct BottomSheetContent: View {
    @Binding var query: String
    @Binding var isSearchActive: Bool
    let detent: BottomSheetDetent
    let contentTopPadding: CGFloat
    let viewModel: CommuteDashboardViewModel
    let searchViewModel: SearchPresentationModel
    let searchActions: SearchActions
    let openSpecialEvent: (SpecialEvent) -> Void

    var body: some View {
        Group {
            if isSearchActive {
                SearchResultsContent(
                    query: $query,
                    viewModel: searchViewModel,
                    actions: searchActions
                )
            } else {
                ScrollView {
                    HomeSheetContent(
                        detent: detent,
                        viewModel: viewModel,
                        openSpecialEvent: openSpecialEvent
                    )
					.padding(.top, contentTopPadding)
					.safeAreaPadding(.horizontal, 16)
                }
            }
        }
    }
}

private struct HomeSheetContent: View {
    let detent: BottomSheetDetent
    let viewModel: CommuteDashboardViewModel
    let openSpecialEvent: (SpecialEvent) -> Void

    var body: some View {
        CommuteDashboardView(
            viewModel: viewModel,
            openSpecialEvent: openSpecialEvent,
            displayStyle: detent == .medium ? .mapsMedium : .regular
        )
    }
}
