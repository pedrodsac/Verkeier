import Foundation

nonisolated protocol GTFSMetadataFetching: Sendable {
    func fetchDataset() async throws -> DataPublicDataset
}

nonisolated struct GTFSMetadataClient: GTFSMetadataFetching {
    static let datasetURL = URL(
        string: "https://data.public.lu/api/1/datasets/5a2a58b9111e9b7f34fc6606/"
    )!

    private let datasetURL: URL
    private let session: URLSession

    init(
        datasetURL: URL = Self.datasetURL,
        session: URLSession = .gtfsUpdateSession
    ) {
        self.datasetURL = datasetURL
        self.session = session
    }

    func fetchDataset() async throws -> DataPublicDataset {
        let (data, response) = try await session.data(from: datasetURL)
        try HTTPResponseValidator.validate(response)
        return try DataPublicDateDecoding.decoder().decode(DataPublicDataset.self, from: data)
    }
}

nonisolated private enum HTTPResponseValidator {
    static func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GTFSUpdateError.serverError(httpResponse.statusCode)
        }
    }
}

extension URLSession {
    nonisolated static var gtfsUpdateSession: URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 180
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }
}
