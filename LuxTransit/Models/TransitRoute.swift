import Foundation

struct TransitRoute: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let shortName: String
    let longName: String?
    let mode: TransportMode
    let operatorName: String?
    let dataSource: DataSource

    init(
        id: String,
        shortName: String,
        longName: String? = nil,
        mode: TransportMode,
        operatorName: String? = nil,
        dataSource: DataSource
    ) {
        self.id = id
        self.shortName = shortName
        self.longName = longName
        self.mode = mode
        self.operatorName = operatorName
        self.dataSource = dataSource
    }
}
