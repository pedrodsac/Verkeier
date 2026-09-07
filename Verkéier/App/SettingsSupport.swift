import Foundation

enum SettingsSupport {
    static func readinessSnapshot(configuration: AppConfiguration) -> DataReadinessSnapshot {
        let items = [
            DataReadinessItem(
                id: "transit",
                title: "Transit data",
                status: "Disconnected",
                detail: "GTFS schedules and the ATP live-data connection are disabled.",
                iconName: "tram.fill"
            ),
            DataReadinessItem(
                id: "avl",
                title: "AVL alerts",
                status: "Available",
                detail: "AVL disruption alerts remain configured.",
                iconName: "exclamationmark.triangle.fill"
            ),
            DataReadinessItem(
                id: "routing",
                title: "Routing",
                status: "MapKit",
                detail: "MapKit routing remains available without transit schedule data.",
                iconName: "point.topleft.down.curvedto.point.bottomright.up"
            )
        ]

        return DataReadinessSnapshot(
            summaryTitle: "Transit data is disconnected",
            summaryMessage: "The interface remains available, but it is not connected to GTFS or the ATP mobiliteit API.",
            items: items
        )
    }

    static func supportBundleText(
        appVersion: String,
        readiness: DataReadinessSnapshot,
        configuration: AppConfiguration,
        generatedAt: Date = .now
    ) -> String {
        let readinessLines = readiness.items.map {
            "\($0.title): \($0.status)\n\($0.detail)"
        }.joined(separator: "\n\n")

        return """
        Verkéier Support Bundle
        Generated: \(generatedAt.formatted(date: .abbreviated, time: .standard))
        App version: \(appVersion)

        Data readiness
        \(readiness.summaryTitle)
        \(readiness.summaryMessage)

        \(readinessLines)

        Endpoints
        AVL: \(configuration.avlMessagesURL.absoluteString)
        """
    }
}
