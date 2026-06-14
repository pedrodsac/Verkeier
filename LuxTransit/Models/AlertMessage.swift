import Foundation

struct AlertMessage: Codable, Hashable, Identifiable, Sendable {
    enum Severity: String, Codable, CaseIterable, Identifiable, Sendable {
        case info
        case warning
        case severe
        case unknown

        var id: String { rawValue }
    }

    let id: String
    let title: String
    let body: String
    let severity: Severity
    let affectedStopIds: [String]
    let affectedRouteIds: [String]
    let startsAt: Date?
    let endsAt: Date?
    let dataSource: DataSource
}
