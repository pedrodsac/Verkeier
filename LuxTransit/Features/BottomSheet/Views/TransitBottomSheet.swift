import SwiftUI

struct TransitBottomSheet: View {
    @Binding var searchQuery: String
    let viewModel: TransitSheetPresentationModel
    let actions: TransitSheetActions

    var body: some View {
        BottomSheetContent(
            viewModel: viewModel,
            searchQuery: $searchQuery,
            actions: actions
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(viewModel.context.accessibilityLabel)
    }
}
