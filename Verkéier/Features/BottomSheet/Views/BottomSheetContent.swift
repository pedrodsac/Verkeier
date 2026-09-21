import SwiftUI

struct BottomSheetContent: View {
    @Binding var query: String
    @Binding var isSearchActive: Bool
    let detent: BottomSheetDetent
    let contentTopPadding: CGFloat
    let viewModel: CommuteDashboardViewModel
    let favouritesViewModel: FavouritesPresentationModel
    let favouritesActions: FavouritesActions
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
				CommuteDashboardView(
					viewModel: viewModel,
					favouritesViewModel: favouritesViewModel,
					favouritesActions: favouritesActions,
					openSpecialEvent: openSpecialEvent,
					displayStyle: detent == .medium ? .mapsMedium : .regular
				)
                .contentMargins(.top, contentTopPadding, for: .scrollContent)
            }
        }
    }
}
