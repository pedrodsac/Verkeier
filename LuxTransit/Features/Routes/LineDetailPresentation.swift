import Foundation

struct LineDetailPresentationModel {
    let route: TransitRoute?
    let detail: LineDetail?
    let alerts: [AlertMessage]
    let errorMessage: String?
}

/// Callbacks the line-detail sheet needs, sliced from ``TransitSheetActions``.
struct LineDetailActions {
    var selectStop: (Stop) -> Void = { _ in }
    var selectDirection: (String) -> Void = { _ in }
}

extension LineDetailActions {
    init(from actions: TransitSheetActions) {
        self.init()
        selectStop = actions.selectStop
        selectDirection = actions.selectLineDetailDirection
    }
}
