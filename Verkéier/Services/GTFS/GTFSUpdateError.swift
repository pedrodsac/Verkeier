import Foundation

nonisolated enum GTFSUpdateError: Error, LocalizedError, Sendable {
    case noGTFSResource
    case missingDownloadURL
    case serverError(Int)
    case downloadFailed
    case invalidArchive
    case unsupportedCompressionMethod(UInt16)
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noGTFSResource:
            return "No GTFS ZIP resource was found."
        case .missingDownloadURL:
            return "The selected GTFS resource has no download URL."
        case .serverError:
            return "The GTFS server returned an error."
        case .downloadFailed:
            return "The GTFS download failed."
        case .invalidArchive:
            return "The GTFS ZIP archive is invalid."
        case .unsupportedCompressionMethod:
            return "The GTFS ZIP archive uses an unsupported compression method."
        case .validationFailed:
            return "The GTFS feed did not pass validation."
        }
    }
}
