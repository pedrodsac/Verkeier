import Foundation

enum SettingsSupport {
    static func readinessSnapshot(
        configuration: AppConfiguration,
        gtfsStatus: GTFSFeedStatus,
        liveTransitLastUpdated: Date?,
        liveTransitErrorMessage: String?
    ) -> DataReadinessSnapshot {
        let gtfsDetail = gtfsDetail(for: gtfsStatus)
        let liveStatus: String
        let liveDetail: String
        if !configuration.hasAPIProxyURL {
            liveStatus = "Not configured"
            liveDetail = "Set API_PROXY_URL to the credential-hiding ATP relay before requesting live departures."
        } else if let liveTransitErrorMessage {
            liveStatus = "Last request failed"
            liveDetail = "Relay configured. \(liveTransitErrorMessage)"
        } else if let liveTransitLastUpdated {
            liveStatus = "Available"
            liveDetail = "Relay configured. Last successful departure board: \(liveTransitLastUpdated.formatted(date: .abbreviated, time: .shortened))."
        } else {
            liveStatus = "Configured"
            liveDetail = "Relay configured; it will be verified with the next live departure-board request."
        }

        let items = [
            DataReadinessItem(
                id: "gtfs",
                title: "GTFS timetable",
                status: gtfsStatus.statusText,
                detail: gtfsDetail,
                iconName: "tram.fill"
            ),
            DataReadinessItem(
                id: "atp",
                title: "ATP live departures",
                status: liveStatus,
                detail: liveDetail,
                iconName: "dot.radiowaves.left.and.right"
            ),
            DataReadinessItem(
                id: "avl",
                title: "AVL alerts",
                status: "Available",
                detail: "AVL disruption alerts are configured separately from the timetable and live-departure feeds.",
                iconName: "exclamationmark.triangle.fill"
            )
        ]

        let summaryTitle: String
        let summaryMessage: String
        if gtfsStatus.isReady, liveStatus == "Available" {
            summaryTitle = "Transit data is ready"
            summaryMessage = "The current GTFS timetable and a recently verified ATP relay are available."
        } else if gtfsStatus.isReady {
            summaryTitle = "Timetable ready"
            summaryMessage = "Static GTFS schedules are available. Live departure availability is shown separately below."
        } else if gtfsStatus.phase == .stale {
            summaryTitle = "Using a cached timetable"
            summaryMessage = "The installed GTFS feed remains usable, but its latest update failed. Review the error below before relying on future dates."
        } else if gtfsStatus.phase == .failed {
            summaryTitle = "Using no timetable feed"
            summaryMessage = "The feed update failed before a valid timetable could be installed. Check the update details below."
        } else {
            summaryTitle = "Preparing timetable data"
            summaryMessage = "Verkéier will download the official Luxembourg GTFS archive before schedule-based transit features become available."
        }

        return DataReadinessSnapshot(
            summaryTitle: summaryTitle,
            summaryMessage: summaryMessage,
            items: items
        )
    }

    private static func gtfsDetail(for status: GTFSFeedStatus) -> String {
        var details = ["Official Luxembourg GTFS archive"]
        if let title = status.resourceTitle { details.append(title) }
        if let downloadedAt = status.downloadedAt {
            details.append("Downloaded \(downloadedAt.formatted(date: .abbreviated, time: .shortened))")
        }
        if let lastCheckedAt = status.lastCheckedAt {
            details.append("Checked \(lastCheckedAt.formatted(date: .abbreviated, time: .shortened))")
        }
        if let validThrough = status.validThrough { details.append("Service through \(validThrough)") }
        if let errorMessage = status.errorMessage { details.append(errorMessage) }
        return details.joined(separator: " · ")
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
        ATP relay: \(configuration.apiProxyURL?.absoluteString ?? "Not configured")
        """
    }
}
