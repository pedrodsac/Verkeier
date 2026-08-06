import Foundation

enum SettingsSupport {
    static func readinessSnapshot(
        configuration: AppConfiguration,
        gtfsSnapshot: GTFSUpdateSnapshot,
        hasBundledSeed: Bool
    ) -> DataReadinessSnapshot {
        let gtfsState: (String, String)
        if let metadata = gtfsSnapshot.metadata {
            gtfsState = (
                "Downloaded cache ready",
                "Using downloaded GTFS data from \(metadata.downloadedAt.formatted(date: .abbreviated, time: .shortened))."
            )
        } else if hasBundledSeed {
            gtfsState = (
                "Bundled seed ready",
                "Using the bundled compact GTFS dataset until a full download completes."
            )
        } else {
            gtfsState = (
                "No GTFS schedule data",
                "Search and offline schedules need a bundled seed or a downloaded GTFS feed."
            )
        }

        let items = [
            DataReadinessItem(
                id: "atp",
                title: "ATP live departures",
                status: configuration.hasATPAccessId ? "Live API configured" : "Mock or unavailable",
                detail: configuration.hasATPAccessId
                    ? "Nearby stops and live departure boards can use the ATP OpenAPI."
                    : "No ATP access ID is configured, so live departure behavior falls back to development-safe data."
                ,
                iconName: "dot.radiowaves.left.and.right"
            ),
            DataReadinessItem(
                id: "gtfs",
                title: "GTFS schedules and search",
                status: gtfsState.0,
                detail: gtfsState.1,
                iconName: "tram.fill"
            ),
            DataReadinessItem(
                id: "avl",
                title: "AVL alerts",
                status: "Live feed configured",
                detail: "Service disruption alerts use \(configuration.avlMessagesURL.host() ?? "the configured AVL feed").",
                iconName: "exclamationmark.triangle.fill"
            ),
            DataReadinessItem(
                id: "routing",
                title: "Routing",
                status: "MapKit transit handoff",
                detail: "Routing uses local GTFS context plus MapKit and Apple Maps for final handoff.",
                iconName: "point.topleft.down.curvedto.point.bottomright.up"
            )
        ]

        let summaryTitle = gtfsSnapshot.metadata == nil && !hasBundledSeed
            ? "Schedule data needs setup"
            : "Transit data is ready"
        let summaryMessage = gtfsSnapshot.lastFailureMessage
            ?? "This screen shows whether Verkéier is currently using live, downloaded, bundled, or fallback data."

        return DataReadinessSnapshot(
            summaryTitle: summaryTitle,
            summaryMessage: summaryMessage,
            items: items
        )
    }

    static func supportBundleText(
        appVersion: String,
        readiness: DataReadinessSnapshot,
        gtfsSnapshot: GTFSUpdateSnapshot,
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

        GTFS
        Status: \(gtfsSnapshot.status.displayText)
        Resource: \(gtfsSnapshot.metadata?.title ?? "Unavailable")
        Downloaded: \(formatted(gtfsSnapshot.metadata?.downloadedAt))
        Last checked: \(formatted(gtfsSnapshot.lastMetadataCheckAt))
        Last modified: \(formatted(gtfsSnapshot.metadata?.lastModified))
        Checksum: \(gtfsSnapshot.metadata?.checksum ?? "Unavailable")
        Last failure: \(gtfsSnapshot.lastFailureMessage ?? "None")

        Endpoints
        ATP: \(configuration.apiBaseURL.absoluteString)
        AVL: \(configuration.avlMessagesURL.absoluteString)
        """
    }

    private static func formatted(_ date: Date?) -> String {
        guard let date else { return "Unavailable" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
