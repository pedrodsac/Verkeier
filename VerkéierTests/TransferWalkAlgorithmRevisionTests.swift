import CryptoKit
import Foundation
import Testing
@testable import Verkeier

/// Tripwire for the stored transfer walk format. The digest covers the strict
/// outcomes of fixed pairs on the bundled walking graph. If it changes, a
/// result-affecting walking change landed: bump
/// `TransferWalkGraphIdentity.algorithmRevision`, then update the golden values.
@Suite("Transfer walk algorithm revision", .serialized)
struct TransferWalkAlgorithmRevisionTests {
    static let goldenRevision = 1
    static let goldenGraphSHA256 = "0dd7dd3357e6962b251aaa494063f092cddc50c16e972f20a618e93df4f1600b"
    static let goldenDigest = "b7541cee8aaad2b9e38902694d2866c66335c0efabd2b01725f9fbcdf481c561"

    @Test("Strict outcomes of fixed pairs match the golden digest")
    func goldenDigest() async throws {
        let fixture = try await TransferWalkEquivalenceTests.Fixture.make()
        defer { fixture.cleanUp() }
        let dataset = try #require(try await fixture.manager.activeDataset())
        let router = fixture.router(mode: .off)
        let prepared = try await router.prepareTransferWalkComputation()
        var hasher = SHA256()
        for (from, to) in TransferWalkEquivalenceTests.pairs {
            let outcome = try await router.transferWalkOutcome(from: from, to: to, dataset: prepared)
            hasher.update(data: try TransferWalkTableCodec.encodePayload(outcome))
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        let sha = dataset.manifest.artifact.sha256.lowercased()
        print("GOLDEN revision=\(TransferWalkGraphIdentity.algorithmRevision) graph=\(sha) digest=\(digest)")
        #expect(sha == Self.goldenGraphSHA256,
                "The bundled walking tiles changed. Regenerate the golden digest and pair it with the new sha256.")
        #expect(TransferWalkGraphIdentity.algorithmRevision == Self.goldenRevision,
                "The algorithm revision changed. Update the golden revision with the new digest.")
        #expect(digest == Self.goldenDigest,
                "Walking results changed without an algorithm revision bump. Bump TransferWalkGraphIdentity.algorithmRevision.")
    }
}
