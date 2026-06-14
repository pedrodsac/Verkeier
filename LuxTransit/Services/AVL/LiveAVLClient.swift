import Foundation

struct LiveAVLClient: AVLClient {
    let feedURL: URL
    var session: URLSession = .shared
    var parser = AVLXMLParser()

    func fetchMessages() async throws -> [AlertMessage] {
        let (data, response) = try await session.data(from: feedURL)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AVLClientError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw AVLClientError.httpStatus(httpResponse.statusCode)
        }
        return try parser.parse(data: data)
    }
}
