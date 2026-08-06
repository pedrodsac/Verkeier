import Foundation

nonisolated enum GTFSResourceSelector {
    static func selectLatestGTFSResource(from dataset: DataPublicDataset) -> DataPublicResource? {
        let candidates = dataset.resources.enumerated().filter { _, resource in
            isGTFSResource(resource) && isZipResource(resource)
        }

        let dated = candidates.filter { $0.element.lastModified != nil }
        if !dated.isEmpty {
            return dated.max { lhs, rhs in
                guard let lhsDate = lhs.element.lastModified,
                      let rhsDate = rhs.element.lastModified else {
                    return lhs.element.lastModified == nil
                }
                if lhsDate == rhsDate {
                    return lhs.offset < rhs.offset
                }
                return lhsDate < rhsDate
            }?.element
        }

        return candidates.last?.element
    }

    static func shouldDownload(remote: DataPublicResource, local: LocalGTFSMetadata?) -> Bool {
        guard let local else { return true }
        if remote.id != local.resourceId { return true }
        if let remoteChecksum = remote.checksumValue, remoteChecksum != local.checksum {
            return true
        }
        return false
    }

    private static func isGTFSResource(_ resource: DataPublicResource) -> Bool {
        let haystack = [
            resource.title,
            resource.latest,
            resource.url
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        return haystack.contains("gtfs")
    }

    private static func isZipResource(_ resource: DataPublicResource) -> Bool {
        if resource.title?.lowercased().hasSuffix(".zip") == true { return true }
        if resource.latest?.lowercased().hasSuffix(".zip") == true { return true }
        if resource.url?.lowercased().hasSuffix(".zip") == true { return true }
        if resource.filetype?.lowercased() == "zip" { return true }
        if resource.mime?.lowercased().contains("zip") == true { return true }
        return false
    }
}
