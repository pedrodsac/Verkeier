import Foundation
import Testing
@testable import LuxTransit

struct GTFSMetadataSelectionTests {
    @Test func selectsNewestGTFSZipResource() throws {
        let older = resource(
            id: "older",
            title: "gtfs-older.zip",
            lastModified: Date(timeIntervalSince1970: 100)
        )
        let newer = resource(
            id: "newer",
            title: "gtfs-newer.zip",
            lastModified: Date(timeIntervalSince1970: 200)
        )

        let selected = GTFSResourceSelector.selectLatestGTFSResource(
            from: DataPublicDataset(resources: [older, newer])
        )

        #expect(selected?.id == "newer")
    }

    @Test func ignoresNonGTFSResources() {
        let selected = GTFSResourceSelector.selectLatestGTFSResource(
            from: DataPublicDataset(
                resources: [
                    resource(id: "shape", title: "shapes.zip", mime: "application/zip"),
                    resource(id: "gtfs", title: "gtfs.zip", mime: "application/zip")
                ]
            )
        )

        #expect(selected?.id == "gtfs")
    }

    @Test func choosesZipResourcesOnly() {
        let selected = GTFSResourceSelector.selectLatestGTFSResource(
            from: DataPublicDataset(
                resources: [
                    resource(id: "json", title: "gtfs.json", mime: "application/json"),
                    resource(id: "zip", title: "gtfs-feed", filetype: "zip")
                ]
            )
        )

        #expect(selected?.id == "zip")
    }

    @Test func usesResourceOrderWhenDatesAreMissing() {
        let selected = GTFSResourceSelector.selectLatestGTFSResource(
            from: DataPublicDataset(
                resources: [
                    resource(id: "first", title: "gtfs-first.zip"),
                    resource(id: "second", title: "gtfs-second.zip")
                ]
            )
        )

        #expect(selected?.id == "second")
    }

    private func resource(
        id: String,
        title: String,
        filetype: String? = nil,
        mime: String? = nil,
        checksum: String? = nil,
        lastModified: Date? = nil
    ) -> DataPublicResource {
        DataPublicResource(
            id: id,
            title: title,
            latest: "https://example.com/\(title)",
            url: nil,
            filetype: filetype,
            mime: mime,
            checksum: checksum.map { DataPublicChecksum(type: "sha256", value: $0) },
            lastModified: lastModified
        )
    }
}
