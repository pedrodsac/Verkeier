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
    struct Recorded {
        let body: Data
        /// Server wait plus transfer of the original request. Client-side time is not replayed:
        /// decoding and CPU contention happen for real.
        let networkMilliseconds: Double
    }
    /// `ROUTING_BENCHMARK_REPLAY_LATENCY=1` answers each board after its recorded network time, so
    /// boards arrive in the original order and the original acquisition overlaps other work.
    static let replaysLatency = ProcessInfo.processInfo.environment["ROUTING_BENCHMARK_REPLAY_LATENCY"] == "1"
    /// `ROUTING_BENCHMARK_REPLAY_ONLY=1` (device replays): a launch without capture bodies fails
    /// before its first search instead of using live transport.
    static let replayOnly = ProcessInfo.processInfo.environment["ROUTING_BENCHMARK_REPLAY_ONLY"] == "1"
    static let bodies: [String: Recorded]? = {
        guard let path = ProcessInfo.processInfo.environment["ROUTING_BENCHMARK_CAPTURE_DIRECTORY"] else { return nil }
        let folder = SimulatorRouteBenchmark.inputURL(path)
        do {
            var result: [String: Recorded] = [:]
            let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where !file.lastPathComponent.contains(".body.") {
                guard let item = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any],
                    let url = (item["url"] as? String).flatMap(URL.init(string:)),
                    let body = item["body"] as? String
                else { continue }
                let bytes = try Data(
                    contentsOf: folder.appendingPathComponent(URL(fileURLWithPath: body).lastPathComponent)
                )
                // Repeated queries resolve deterministically in capture-file order.
                let key = key(url)
                let transaction = ((item["transport"] as? [String: Any])?["transactions"] as? [[String: Any]])?.first
                let network = ["responseWaitMilliseconds", "transferMilliseconds"].reduce(0.0) {
                    $0 + max(0, (transaction?[$1] as? Double) ?? 0)
                }
                if result[key] == nil { result[key] = Recorded(body: bytes, networkMilliseconds: network) }
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
