import SwiftUI

struct TransitBottomSheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var selectedDetent: BottomSheetDetent
    @Binding var searchQuery: String
    let viewModel: TransitSheetPresentationModel
    let actions: TransitSheetActions

    @GestureState private var dragTranslation: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let sheetHeight = height * 0.88
            let baseOffset = offset(
                for: selectedDetent, containerHeight: height, sheetHeight: sheetHeight)
            let maximumOffset = offset(
                for: .collapsed, containerHeight: height, sheetHeight: sheetHeight)
            let adjustedOffset = clampedOffset(
                baseOffset + dragTranslation, maximumOffset: maximumOffset)

            sheet(
                baseOffset: baseOffset,
                containerHeight: height,
                sheetHeight: sheetHeight
            )
            .frame(width: proxy.size.width, height: sheetHeight, alignment: .top)
            .background(
                .regularMaterial,
                in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
            )
            .overlay(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                    .stroke(.white.opacity(0.28), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.16), radius: 24, y: -6)
            .position(
                x: proxy.size.width / 2,
                y: height - (sheetHeight / 2) + adjustedOffset
            )
            .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: selectedDetent)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(viewModel.context.accessibilityLabel)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func sheet(
        baseOffset: CGFloat,
        containerHeight: CGFloat,
        sheetHeight: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            BottomSheetHandle(detent: selectedDetent)
                .highPriorityGesture(
                    sheetDragGesture(
                        baseOffset: baseOffset,
                        containerHeight: containerHeight,
                        sheetHeight: sheetHeight
                    )
                )
                .onTapGesture {
                    selectedDetent = selectedDetent.toggledFromHandleTap
                }
                .accessibilityAdjustableAction { direction in
                    selectedDetent = selectedDetent.detent(after: direction)
                }

            BottomSheetContent(
                viewModel: viewModel,
                searchQuery: $searchQuery,
                actions: actions
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func sheetDragGesture(
        baseOffset: CGFloat,
        containerHeight: CGFloat,
        sheetHeight: CGFloat
    ) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                selectedDetent = targetDetent(
                    predictedOffset: baseOffset + value.predictedEndTranslation.height,
                    containerHeight: containerHeight,
                    sheetHeight: sheetHeight
                )
            }
    }

    private func offset(
        for detent: BottomSheetDetent,
        containerHeight: CGFloat,
        sheetHeight: CGFloat
    ) -> CGFloat {
        switch detent {
        case .collapsed:
            max(0, sheetHeight - 132)
        case .medium:
            max(0, sheetHeight - (containerHeight * 0.58))
        case .expanded:
            0
        }
    }

    private func targetDetent(
        predictedOffset: CGFloat,
        containerHeight: CGFloat,
        sheetHeight: CGFloat
    ) -> BottomSheetDetent {
        let maximumOffset = offset(for: .collapsed, containerHeight: containerHeight, sheetHeight: sheetHeight)
        let predictedOffset = clampedOffset(predictedOffset, maximumOffset: maximumOffset)

        return BottomSheetDetent.allCases.min { lhs, rhs in
            abs(
                offset(for: lhs, containerHeight: containerHeight, sheetHeight: sheetHeight)
                    - predictedOffset)
                < abs(
                    offset(for: rhs, containerHeight: containerHeight, sheetHeight: sheetHeight)
                        - predictedOffset)
        } ?? .medium
    }

    private func clampedOffset(_ offset: CGFloat, maximumOffset: CGFloat) -> CGFloat {
        min(max(0, offset), maximumOffset)
    }
}

private struct BottomSheetHandle: View {
    let detent: BottomSheetDetent

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.secondary.opacity(0.45))
                .frame(width: 38, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 11)
        }
        .frame(maxWidth: .infinity, minHeight: 32)
        .contentShape(Rectangle())
        .accessibilityLabel("Bottom sheet drag handle")
        .accessibilityValue(detent.accessibilityLabel)
        .accessibilityHint("Drag, swipe up or down, or tap to change the sheet height.")
    }
}
