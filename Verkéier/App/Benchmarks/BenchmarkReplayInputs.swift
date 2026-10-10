#if targetEnvironment(simulator) || ROUTING_BENCHMARK
import Foundation

struct BenchmarkBikeShareService: BikeShareService {
    let value: BikeShareSnapshot
    func bikeShareStations(near location: LocationPoint) async -> [BikeShareStation] { value.stations }
    func refreshStaticStations() async {}
    func refreshAvailability() async {}
    func snapshot() async -> BikeShareSnapshot? { value }
}

/// Replay requires the same board query as the capture; missing evidence is an error.
nonisolated enum BenchmarkRecordedTransport {
    static let bodies: [String: Data]? = {
        guard let path = ProcessInfo.processInfo.environment["ROUTING_BENCHMARK_CAPTURE_DIRECTORY"] else { return nil }
        let folder = URL(fileURLWithPath: path)
        do {
            var result: [String: Data] = [:]
            let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where !file.lastPathComponent.contains(".body.") {
                guard let item = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any],
                      let url = (item["url"] as? String).flatMap(URL.init(string:)),
                      let body = item["body"] as? String else { continue }
                let bytes = try Data(contentsOf: folder.appendingPathComponent(URL(fileURLWithPath: body).lastPathComponent))
                // Repeated queries resolve deterministically in capture-file order.
                let key = key(url)
                if result[key] == nil { result[key] = bytes }
            }
            return result
        } catch { return [:] }
    }()
    static func key(_ url: URL) -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let ignored: Set<String> = ["accessid", "apikey", "key", "token", "requestid"]
        let query = items.filter { !ignored.contains($0.name.lowercased()) }
            .sorted { ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "") }
            .map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
        return url.lastPathComponent + "?" + query
    }
}
#endif
