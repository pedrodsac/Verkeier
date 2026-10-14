import Foundation

nonisolated enum TransferWalkMode: Equatable, Sendable {
    case on
    /// Never consult stored walks (A/B measurements and tests).
    case off
    /// Consult stored walks but recompute live on every hit and fail on a mismatch.
    case verify
}

nonisolated enum TransferWalkSettings {
    /// True in the XCTest / Swift Testing host, which must never touch the real store.
    static var isTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    static var mode: TransferWalkMode {
        if isTestHost { return .off }
        #if DEBUG || ROUTING_BENCHMARK || targetEnvironment(simulator)
        switch ProcessInfo.processInfo.environment["ROUTING_TRANSFER_WALKS"] {
        case "0": return .off
        case "verify": return .verify
        default: break
        }
        if CommandLine.arguments.contains("--disable-transfer-walks") { return .off }
        #endif
        return .on
    }

    /// Benchmarks can build into a separate directory without touching the app's table.
    static var storeDirectoryOverride: URL? {
        #if DEBUG || ROUTING_BENCHMARK || targetEnvironment(simulator)
        if let path = ProcessInfo.processInfo.environment["ROUTING_TRANSFER_WALKS_DIRECTORY"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        return nil
    }
}
