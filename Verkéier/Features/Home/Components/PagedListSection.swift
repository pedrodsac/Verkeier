import SwiftData
import SwiftUI

/// A horizontally paged sequence of native inset-grouped list sections.
///
/// A `Section` gets its grouped styling only when hosted by a `List`, so each
/// page owns a small, non-scrolling list rather than recreating rows manually.
struct PagedListSection<Item, Row: View>: View {
    private let items: [Item]
    private let row: (Item) -> Row
    /// Leaves 16pt of the next inset-grouped section visible after accounting
    /// for that list's own 16pt leading margin.
    private let pagePeekWidth: CGFloat = 16

    @ScaledMetric(relativeTo: .body) private var standardRowHeight: CGFloat = 50
    @ScaledMetric(relativeTo: .body) private var sectionVerticalMargins: CGFloat = 50

    let favorite: Bool

    init(items: [Item], @ViewBuilder row: @escaping (Item) -> Row, favorite: Bool = false) {
        self.items = items
        self.row = row
        self.favorite = favorite
    }

    private var pages: [[Item]] {
        stride(from: 0, to: items.count, by: 3).map { startIndex in
            Array(items[startIndex..<min(startIndex + 3, items.count)])
        }
    }

    private var hasMultiplePages: Bool {
        pages.count > 1
    }

    private var pageSpacing: CGFloat {
        hasMultiplePages ? -16 : 0
    }

    private var pageWidthReduction: CGFloat {
        hasMultiplePages ? pagePeekWidth : 0
    }

    /// Three standard dashboard rows plus the native grouped-section margins.
    /// `@ScaledMetric` lets this grow alongside Dynamic Type.
    private var pageHeight: CGFloat {
        (standardRowHeight * 3) + sectionVerticalMargins
    }

    var body: some View {
        ScrollView(.horizontal) {
            // The overlap reclaims the inner lists' adjoining 16pt margins:
            // cards gain 16pt without losing the next-card preview. A lone
            // page uses the full width because there is nothing to preview.
            LazyHStack(spacing: pageSpacing) {
                ForEach(pages.indices, id: \.self) { index in
                    List {
                        Section {
                            ForEach(pages[index].indices, id: \.self) { itemIndex in
                                row(pages[index][itemIndex])
                            }
                        }
                        .listRowBackground(favorite ? Color.yellow.opacity(0.12) : nil)
                    }
                    .listStyle(.insetGrouped)
                    .scrollDisabled(true)
                    .scrollContentBackground(.hidden)
                    // The nested list otherwise adds a scroll-content inset
                    // above its section, leaving a gap below the outer header
                    // and consuming the space reserved for the third row.
                    .contentMargins(.top, 0, for: .scrollContent)
                    .frame(height: pageHeight)
                    .containerRelativeFrame(.horizontal) { width, _ in
                        max(0, width - pageWidthReduction)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .frame(height: pageHeight)
        .scrollTargetBehavior(ViewAlignedScrollTargetBehavior(limitBehavior: .alwaysByOne))
        .scrollIndicators(.hidden)
    }
}
