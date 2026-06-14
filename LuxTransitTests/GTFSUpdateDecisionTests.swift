import Foundation
import Testing
@testable import LuxTransit

struct GTFSUpdateDecisionTests {
    @Test func shouldDownloadWhenLocalMetadataIsMissing() {
        #expect(GTFSResourceSelector.shouldDownload(remote: remote(), local: nil))
    }

    @Test func shouldDownloadWhenResourceIdChanges() {
        let local = metadata(resourceId: "old", checksum: "abc")

        #expect(GTFSResourceSelector.shouldDownload(remote: remote(id: "new", checksum: "abc"), local: local))
    }

    @Test func shouldDownloadWhenChecksumChanges() {
        let local = metadata(resourceId: "same", checksum: "abc")

        #expect(GTFSResourceSelector.shouldDownload(remote: remote(id: "same", checksum: "def"), local: local))
    }

    @Test func shouldNotDownloadWhenResourceIdAndChecksumMatch() {
        let local = metadata(resourceId: "same", checksum: "abc")

        #expect(!GTFSResourceSelector.shouldDownload(remote: remote(id: "same", checksum: "abc"), local: local))
    }

    private func remote(id: String = "same", checksum: String? = "abc") -> DataPublicResource {
        DataPublicResource(
            id: id,
            title: "gtfs.zip",
            latest: "https://example.com/gtfs.zip",
            url: nil,
            filetype: "zip",
            mime: "application/zip",
            checksum: checksum.map { DataPublicChecksum(type: "sha256", value: $0) },
            lastModified: nil
        )
    }

    private func metadata(resourceId: String, checksum: String?) -> LocalGTFSMetadata {
        LocalGTFSMetadata(
            resourceId: resourceId,
            title: "GTFS",
            checksum: checksum,
            lastModified: nil,
            downloadedAt: Date(timeIntervalSince1970: 100),
            indexedAt: Date(timeIntervalSince1970: 100)
        )
    }
}
