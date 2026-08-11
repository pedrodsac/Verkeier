import SwiftUI

struct BottomSheetContent: View {
    @Binding var query: String
    @Binding var isSearchActive: Bool
    let detent: BottomSheetDetent
    let contentTopPadding: CGFloat
    let viewModel: CommuteDashboardViewModel
    let searchViewModel: SearchPresentationModel
    let searchActions: SearchActions

    var body: some View {
        Group {
            if isSearchActive {
                SearchResultsContent(
                    query: $query,
                    viewModel: searchViewModel,
                    actions: searchActions
                )
            } else if detent == .collapsed {
                EmptyView()
            } else {
                ScrollView {
                    HomeSheetContent(detent: detent, viewModel: viewModel)
                }
            }
        }
        .padding(.top, contentTopPadding)
        .safeAreaPadding(.horizontal, 16)
    }
}

private struct HomeSheetContent: View {
    let detent: BottomSheetDetent
    let viewModel: CommuteDashboardViewModel

    var body: some View {
        CommuteDashboardView(
            viewModel: viewModel,
            displayStyle: detent == .medium ? .mapsMedium : .regular
        )
    }
}
