#if targetEnvironment(simulator) || ROUTING_BENCHMARK
import Foundation

nonisolated final class BenchmarkBoardProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host() == "recorded-atp.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        // A silent fixture exercises the entire acquisition budget; URLSession
        // cancellation at the deadline calls stopLoading and ends the request.
        if ProcessInfo.processInfo.environment["ROUTING_BENCHMARK_SCENARIO"] == "deadline-arrive" { return }
        do {
            let stop = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?
                .first { $0.name == "id" }?.value
            let body: Data
            if let bodies = BenchmarkRecordedTransport.bodies {
                guard let captured = bodies[BenchmarkRecordedTransport.key(request.url!)] else {
                    print("ROUTING_BENCHMARK_ABORT missing-replay-query"); fflush(stdout)
                    throw CocoaError(.fileReadNoSuchFile)
                }
                body = captured
            } else if stop == "000220402034", let path = ProcessInfo.processInfo.environment["ROUTING_BENCHMARK_FIXTURE"] {
                body = try Data(contentsOf: SimulatorRouteBenchmark.inputURL(path))
            } else { body = Data("{\"Departure\":[]}".utf8) }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
#endif
