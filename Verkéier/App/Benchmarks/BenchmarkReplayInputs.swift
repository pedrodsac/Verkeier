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
        /// The query without its `lines`, and those lines (empty: an unrestricted board).
        var window = ""
        var lines: [String] = []
    }
    /// `ROUTING_BENCHMARK_REPLAY_APPROXIMATE=1`: a board query that was never recorded is assembled
    /// from recorded boards of the same stop and window, row by row for each requested line. This is
    /// **approximate**: it holds only the rows of lines some recorded board of that window covers,
    /// each row as observed when that board was recorded. Every such query is printed as
    /// `ROUTING_BENCHMARK_REPLAY_APPROXIMATE <json>`; a line no recorded board covers is listed as missing.
    static let replaysApproximately = ProcessInfo.processInfo.environment["ROUTING_BENCHMARK_REPLAY_APPROXIMATE"] == "1"
    /// `ROUTING_BENCHMARK_REPLAY_APPROXIMATE_LATENCY=<stop|*>=<ms>,...` replaces the network time of an
    /// approximated board (default: the slowest source board's). A wider board answers more slowly than
    /// the narrow boards it is assembled from, so this is the knob for a latency sensitivity run.
    static let approximateLatencies: [String: Double] = {
        let text = ProcessInfo.processInfo.environment["ROUTING_BENCHMARK_REPLAY_APPROXIMATE_LATENCY"] ?? ""
        return Dictionary(
            text.split(separator: ",").compactMap { item -> (String, Double)? in
                let parts = item.split(separator: "=")
                guard parts.count == 2, let value = Double(parts[1]) else { return nil }
                return (String(parts[0]), value)
            },
            uniquingKeysWith: { $1 }
        )
    }()
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
                if result[key] == nil {
                    result[key] = Recorded(
                        body: bytes,
                        networkMilliseconds: network,
                        window: windowKey(url),
                        lines: lines(in: url)
                    )
                }
            }
            return result
        } catch { return [:] }
    }()
    static func key(_ url: URL, excluding extra: Set<String> = []) -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let ignored = Set(["accessid", "apikey", "key", "token", "requestid"]).union(extra)
        let query = items.filter { !ignored.contains($0.name.lowercased()) }
            .sorted { ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "") }
            .map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
        return url.lastPathComponent + "?" + query
    }
    static func windowKey(_ url: URL) -> String { key(url, excluding: ["lines"]) }
    static func lines(in url: URL) -> [String] {
        let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == "lines" }?.value
        return value?.split(separator: ",").map(String.init) ?? []
    }

    /// The board for a filtered query that was not recorded, assembled from recorded boards of the same
    /// window (see `replaysApproximately`). Nil when the mode is off, the query is unfiltered, or no
    /// recorded board of that window covers any requested line.
    static func approximation(for url: URL) -> Recorded? {
        guard replaysApproximately, let bodies else { return nil }
        let wanted = lines(in: url)
        let window = windowKey(url)
        guard !wanted.isEmpty else { return nil }
        let candidates = bodies.filter { $0.value.window == window }.sorted { $0.key < $1.key }
        var rows: [[String: Any]] = []
        var sources: [String] = []
        var missing: [String] = []
        var delay = 0.0
        var template: [String: Any]?
        var seen: Set<String> = []
        for line in wanted {
            guard
                let source = candidates.first(where: { $0.value.lines.isEmpty || $0.value.lines.contains(line) }),
                let object = try? JSONSerialization.jsonObject(with: source.value.body) as? [String: Any]
            else { missing.append(line); continue }
            if template == nil { template = object }
            if !sources.contains(source.key) { sources.append(source.key) }
            delay = max(delay, source.value.networkMilliseconds)
            for row in object["Departure"] as? [[String: Any]] ?? [] where Self.line(of: row) == line {
                let identity =
                    ((row["JourneyDetailRef"] as? [String: Any])?["ref"] as? String ?? "") + "|"
                    + (row["stopExtId"] as? String ?? "") + "|" + (row["date"] as? String ?? "")
                    + (row["time"] as? String ?? "")
                if seen.insert(identity).inserted { rows.append(row) }
            }
        }
        guard var body = template, !sources.isEmpty else { return nil }
        let stop = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "id" }?.value
        if let override = stop.flatMap({ approximateLatencies[$0] }) ?? approximateLatencies["*"] { delay = override }
        rows.sort { Self.plannedKey($0) < Self.plannedKey($1) }
        body["Departure"] = rows
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        let report: [String: Any] = [
            "key": key(url), "requestedLines": wanted, "sources": sources, "missingLines": missing,
            "rows": rows.count, "networkMilliseconds": delay,
        ]
        if let json = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
            let text = String(data: json, encoding: .utf8)
        {
            print("ROUTING_BENCHMARK_REPLAY_APPROXIMATE " + text); fflush(stdout)
        }
        return Recorded(body: data, networkMilliseconds: delay, window: window, lines: wanted)
    }
    private static func line(of row: [String: Any]) -> String? {
        if let stop = row["ProductAtStop"] as? [String: Any], let line = stop["line"] as? String { return line }
        if let products = row["Product"] as? [[String: Any]] { return products.first?["line"] as? String }
        return (row["Product"] as? [String: Any])?["line"] as? String
    }
    private static func plannedKey(_ row: [String: Any]) -> String {
        (row["date"] as? String ?? "") + " " + (row["time"] as? String ?? "")
    }
}
#endif
