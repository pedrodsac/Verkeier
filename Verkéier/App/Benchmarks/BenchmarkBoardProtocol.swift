#if targetEnvironment(simulator) || ROUTING_BENCHMARK
import Foundation
import os

nonisolated final class BenchmarkBoardProtocol: URLProtocol {
    private let pending = OSAllocatedUnfairLock<DispatchWorkItem?>(initialState: nil)
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
            var delay = 0.0
            if let bodies = BenchmarkRecordedTransport.bodies {
                guard let captured = bodies[BenchmarkRecordedTransport.key(request.url!)] else {
                    print(
                        "ROUTING_BENCHMARK_ABORT missing-replay-query \(BenchmarkRecordedTransport.key(request.url!))"
                    ); fflush(stdout)
                    throw CocoaError(.fileReadNoSuchFile)
                }
                body = captured.body
                if BenchmarkRecordedTransport.replaysLatency { delay = captured.networkMilliseconds }
            } else if stop == "000220402034",
                let path = ProcessInfo.processInfo.environment["ROUTING_BENCHMARK_FIXTURE"]
            {
                body = try Data(contentsOf: SimulatorRouteBenchmark.inputURL(path))
            } else {
                body = Data("{\"Departure\":[]}".utf8)
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            guard delay > 0 else { deliver(response, body); return }
            let item = DispatchWorkItem { [weak self] in self?.deliver(response, body) }
            pending.withLock { $0 = item }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay / 1_000, execute: item)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    private func deliver(_ response: HTTPURLResponse, _ body: Data) {
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    /// A cancelled request (the acquisition deadline) must not be answered afterwards.
    override func stopLoading() { pending.withLock { $0?.cancel() } }
}
#endif
