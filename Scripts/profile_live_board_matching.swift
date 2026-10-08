import Foundation
import MobiliteitKit

final class RecordedBoardProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var capture = false
    nonisolated(unsafe) static var folder = FileManager.default.temporaryDirectory
    private let taskLock = NSLock()
    private var pending: Task<Void, Never>?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let req = request
        taskLock.withLock {
            pending = Task { [self] in
                do {
                    let id = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "id" }!.value!
                    let file = Self.folder.appendingPathComponent(id + ".json")
                    let data: Data
                    if Self.capture {
                        let response = try await URLSession.shared.data(for: req)
                        guard (response.1 as? HTTPURLResponse)?.statusCode == 200 else {
                            throw URLError(.badServerResponse)
                        }
                        data = response.0
                        try data.write(to: file)
                    } else { data = try Data(contentsOf: file) }
                    guard !Task.isCancelled else { return }
                    let http = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"])!
                    client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
                    client?.urlProtocol(self, didLoad: data)
                    client?.urlProtocolDidFinishLoading(self)
                } catch { client?.urlProtocol(self, didFailWithError: error) }
            }
        }
    }
    override func stopLoading() { taskLock.withLock { pending?.cancel() } }
}
@main struct BoardReplay {
    static func main() async throws {
        // Explicit capture is the only mode that contacts the provider. Replay
        // uses recorded public boards and an existing installed GTFS database.
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count >= 4, ["capture", "replay"].contains(args[0]),
              args[0] != "capture" || args.count == 5 else {
            print("Usage: profile-live-boards capture|replay DATABASE RECORDING_FOLDER OUTPUT_JSON [PROXY_URL]")
            return
        }
        let capture = args[0] == "capture"
        RecordedBoardProtocol.folder = URL(fileURLWithPath: args[2], isDirectory: true)
        RecordedBoardProtocol.capture = capture
        let folder = RecordedBoardProtocol.folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let anchorFile = folder.appendingPathComponent("anchor.txt")
        let anchor: Date
        if capture {
            anchor = .now
            try String(anchor.timeIntervalSince1970).write(to: anchorFile, atomically: true, encoding: .utf8)
        } else { anchor = Date(timeIntervalSince1970: Double(try String(contentsOf: anchorFile, encoding: .utf8))!) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordedBoardProtocol.self]
        let client = MobiliteitAPIClient(apiKey: "", baseURL: URL(string: capture ? args[4] : "https://recorded-boards.invalid")!, session: URLSession(configuration: config), language: "en")
        let provider = try HafasRealtimeRoutingProvider(databaseURL: URL(fileURLWithPath: args[1]), client: client, maximumConcurrentBoardRequests: 16)
        let ids = ["000200409005", "000200417050", "000200417052", "000200508002", "000200508003", "000200508004", "000200508016"]
        let request = RealtimeRoutingRequest(stopIDs: ids, from: anchor, through: anchor.addingTimeInterval(10_800), refreshPolicy: .forceRefresh, maximumConcurrentRequests: 16, timeout: .seconds(30), deadline: .now.advanced(by: .seconds(30)))
        let start = ContinuousClock.now
        let batch = try await provider.patches(for: request)
        print("capture", capture, "elapsed", start.duration(to: .now), "matching", batch.boardMatchingMilliseconds, "fetch", batch.boardFetchMilliseconds, "preparation", batch.scheduledPreparationMilliseconds, "patches", batch.patches.count, "rejections", batch.matchingRejections, "incomplete", batch.incompleteStopIDs)
        var records: [[String: Any]] = []
        for p in batch.patches {
            var events: [[String: Any]] = []
            for e in p.events {
                var row: [String: Any] = ["stop": e.stopID, "sequence": e.stopSequence ?? -1]
                row["departure"] = e.effectiveDeparture?.timeIntervalSince1970 ?? 0
                row["arrival"] = e.effectiveArrival?.timeIntervalSince1970 ?? 0
                row["departureSource"] = String(describing: e.departureSource)
                row["arrivalSource"] = String(describing: e.arrivalSource)
                events.append(row)
            }
            records.append(["trip": p.tripID, "date": p.serviceDate.compactString, "status": String(describing: p.status), "events": events])
        }
        try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys]).write(to: URL(fileURLWithPath: args[3]))
    }
}
