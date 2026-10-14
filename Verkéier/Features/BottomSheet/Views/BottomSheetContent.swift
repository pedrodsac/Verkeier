import SwiftUI

struct BottomSheetContent: View {
    @Binding var isSearchActive: Bool
    let detent: BottomSheetDetent
    let contentTopPadding: CGFloat
    let viewModel: CommuteDashboardViewModel
    let favouritesViewModel: FavouritesPresentationModel
    let favouritesActions: FavouritesActions
    let openSpecialEvent: (SpecialEvent) -> Void

    var body: some View {
        Group {
            if isSearchActive {
                SearchResultsContent()
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
