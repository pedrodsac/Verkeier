import Foundation

struct DataReadinessSnapshot: Sendable {
    let summaryTitle: String
    let summaryMessage: String
    let items: [DataReadinessItem]
}

struct DataReadinessItem: Identifiable, Sendable {
    let id: String
    let title: String
    let status: String
    let detail: String
    let iconName: String
}
