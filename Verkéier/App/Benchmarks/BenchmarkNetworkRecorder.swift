#if targetEnvironment(simulator) || ROUTING_BENCHMARK
import Foundation
import MobiliteitKit
import os

/// Only installed by the explicit benchmark launch argument.
nonisolated final class BenchmarkNetworkRecorder: Sendable {
    static let shared = BenchmarkNetworkRecorder()
    private struct State: Sendable { var requests = 0; var stopped = false }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let budget = Int(ProcessInfo.processInfo.environment["ROUTING_BENCHMARK_REQUEST_BUDGET"] ?? "200") ?? 200
    private enum Limit: Error { case requestBudget, quota }
    var observer: HTTPDiagnosticsObserver {
        .init(willSend: { [self] _ in
            try state.withLock { state in
                guard !state.stopped else { throw Limit.quota }
                guard state.requests < budget else {
                    state.stopped = true
                    print("ROUTING_BENCHMARK_ABORT request-budget"); fflush(stdout)
                    throw Limit.requestBudget
                }
                state.requests += 1
                print("ROUTING_NETWORK_REQUEST \(state.requests)"); fflush(stdout)
            }
        }, didReceive: { [self] response in
            if response.statusCode == 429 {
                state.withLock { $0.stopped = true }
                print("ROUTING_BENCHMARK_ABORT quota"); fflush(stdout)
            } else if response.statusCode >= 400 || response.successfulBody == nil {
                state.withLock { $0.stopped = true }
                print("ROUTING_BENCHMARK_ABORT provider-error-\(response.statusCode)"); fflush(stdout)
            }
            do {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("routing-network-capture", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let id = UUID().uuidString
                var metadata: [String: Any] = ["url": response.request.absoluteString,
                    "status": response.statusCode, "receivedAt": response.receivedAt.timeIntervalSince1970]
                if let transport = response.transport {
                    metadata["transport"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(transport))
                }
                if let body = response.successfulBody {
                    let bodyFile = folder.appendingPathComponent(id + ".body.json")
                    try body.write(to: bodyFile, options: .atomic)
                    metadata["body"] = bodyFile.path
                }
                let file = folder.appendingPathComponent(id + ".json")
                try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]).write(to: file, options: .atomic)
                print("ROUTING_NETWORK_FILE " + file.path); fflush(stdout)
            } catch { print("ROUTING_BENCHMARK_ABORT capture-failed"); fflush(stdout) }
        })
    }
}
#endif
