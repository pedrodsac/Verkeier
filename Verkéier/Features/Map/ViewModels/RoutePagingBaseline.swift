import Foundation

/// Routes listed when the user pressed Earlier or Later. Paging only appends
/// to these; they stay exactly as shown until a full calculation replaces them.
nonisolated struct RoutePagingBaseline {
    private(set) var primary: [RouteOption]
    private(set) var supplemental: [RouteOption]
    private(set) var visiblePrimary: [RouteOption]
    private(set) var visibleSupplemental: [RouteOption]
    private(set) var ids: Set<String>

    init(primary: [RouteOption], supplemental: [RouteOption],
         visiblePrimary: [RouteOption], visibleSupplemental: [RouteOption]) {
        self.primary = primary
        self.supplemental = supplemental
        self.visiblePrimary = visiblePrimary
        self.visibleSupplemental = visibleSupplemental
        ids = Set((primary + supplemental + visiblePrimary + visibleSupplemental).map(\.id))
    }

    /// Applies an explicit single-journey refresh; `nil` removes an invalidated journey.
    func replacing(_ id: String, with option: RouteOption?) -> Self {
        func replaced(in options: [RouteOption]) -> [RouteOption] {
            options.compactMap { $0.id == id ? option : $0 }
        }
        return .init(primary: replaced(in: primary), supplemental: replaced(in: supplemental),
                     visiblePrimary: replaced(in: visiblePrimary),
                     visibleSupplemental: replaced(in: visibleSupplemental))
    }
}
