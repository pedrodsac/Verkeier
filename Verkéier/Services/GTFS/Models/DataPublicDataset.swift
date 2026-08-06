import Foundation

nonisolated struct DataPublicDataset: Decodable, Sendable {
    let resources: [DataPublicResource]
}

nonisolated struct DataPublicResource: Decodable, Identifiable, Sendable {
    let id: String
    let title: String?
    let latest: String?
    let url: String?
    let filetype: String?
    let mime: String?
    let checksum: DataPublicChecksum?
    let lastModified: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case latest
        case url
        case filetype
        case mime
        case checksum
        case lastModified = "last_modified"
    }

    var downloadURL: URL? {
        [latest, url].compactMap { $0 }.compactMap(URL.init(string:)).first
    }

    var checksumValue: String? {
        checksum?.value
    }
}

nonisolated struct DataPublicChecksum: Decodable, Sendable {
    let type: String?
    let value: String?
}

nonisolated enum DataPublicDateDecoding {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = iso8601WithFractionalSeconds.date(from: value)
                ?? iso8601.date(from: value)
                ?? plainDate.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported date format: \(value)"
            )
        }
        return decoder
    }

    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601 = ISO8601DateFormatter()

    private static let plainDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
