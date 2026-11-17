import Foundation
import Testing
@testable import CairnInferenceLocal

struct ModelDownloadManagerTests {
    private let digest = SHA256Digest.hex(of: Data("payload".utf8))

    private func listing(withDigest digest: String?) -> [ModelFileListing] {
        [
            ModelFileListing(name: "config.json", bytes: 7, sha256: digest),
            ModelFileListing(name: "model.safetensors", bytes: 7, sha256: digest),
        ]
    }

    private func scratch() -> (ModelStoreLayout, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cairn-dl-\(UUID().uuidString)", isDirectory: true)
        return (ModelStoreLayout(rootURL: root), root)
    }

    private func stub(_ outcomes: [String: ModelDownloadOutcome] = [:], calls: Recorder = Recorder()) -> StubDownloader {
        StubDownloader(outcomes: outcomes, payload: Data("payload".utf8), calls: calls)
    }

    @Test func refusesBeforeAnyRequestWithoutTheOptIn() async {
        let (layout, root) = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let events = Recorder()
        let manager = ModelDownloadManager(
            downloader: stub(), layout: layout, gate: OutboundGate(optedIn: false)
        )
        let outcome = await manager.install(repoID: "org/model", listing: listing(withDigest: digest)) {
            events.record("\($0)")
        }
        #expect(outcome == .failed(.outboundNotOptedIn))
        #expect(events.recorded.isEmpty)
    }

    @Test func rejectsARepoIDThatIsNotAModelName() async {
        let (layout, root) = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = ModelDownloadManager(
            downloader: stub(), layout: layout, gate: OutboundGate(optedIn: true)
        )
        let outcome = await manager.install(
            repoID: "https://example.invalid/a/b", listing: listing(withDigest: digest)
        ) { _ in }
        #expect(outcome == .failed(.invalidRepoID))
    }

    @Test func installsVerifiesAndWritesTheManifestLast() async throws {
        let (layout, root) = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let calls = Recorder()
        let manager = ModelDownloadManager(
            downloader: stub(calls: calls), layout: layout, gate: OutboundGate(optedIn: true)
        )
        let events = Recorder()
        let outcome = await manager.install(repoID: "org/model", listing: listing(withDigest: digest)) {
            events.record("\($0)")
        }
        guard case .installed(let bytes) = outcome else {
            Issue.record("expected installed, got \(outcome)"); return
        }
        #expect(bytes == 14)
        let manifest = try #require(await manager.manifest(repoID: "org/model"))
        #expect(manifest.files.count == 2)
        #expect(manifest.files.allSatisfy { $0.sha256 == digest })
        #expect(calls.recorded == ["fetch:config.json", "fetch:model.safetensors"])
        #expect(events.recorded.first?.hasPrefix("planned(fileCount: 2") == true)
        #expect(events.recorded.last?.hasPrefix("completed(totalBytes: 14") == true)
    }

    @Test func aWrongChecksumStopsTheInstall() async {
        let (layout, root) = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = ModelDownloadManager(
            downloader: stub(), layout: layout, gate: OutboundGate(optedIn: true)
        )
        let outcome = await manager.install(
            repoID: "org/model", listing: listing(withDigest: String(repeating: "0", count: 64))
        ) { _ in }
        #expect(outcome == .failed(.verificationFailed))
        #expect(await manager.manifest(repoID: "org/model") == nil)
    }

    @Test func aPausedFileResumesFromTheStoredBlock() async {
        let (layout, root) = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let calls = Recorder()
        let firstManager = ModelDownloadManager(
            downloader: stub(["config.json": .paused(resumeData: Data([1, 2, 3, 4]))], calls: calls),
            layout: layout, gate: OutboundGate(optedIn: true)
        )
        let first = await firstManager.install(repoID: "org/model", listing: listing(withDigest: digest)) { _ in }
        #expect(first == .paused(at: "config.json"))

        let secondManager = ModelDownloadManager(
            downloader: stub(calls: calls), layout: layout, gate: OutboundGate(optedIn: true)
        )
        let second = await secondManager.install(repoID: "org/model", listing: listing(withDigest: digest)) { _ in }
        guard case .installed = second else { Issue.record("expected installed, got \(second)"); return }
        #expect(calls.recorded.contains("resume:4"))
    }

    @Test func uninstallRemovesTheModelAndItsRecord() async {
        let (layout, root) = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = ModelDownloadManager(
            downloader: stub(), layout: layout, gate: OutboundGate(optedIn: true)
        )
        _ = await manager.install(repoID: "org/model", listing: listing(withDigest: digest)) { _ in }
        await manager.uninstall(repoID: "org/model")
        #expect(!FileManager.default.fileExists(atPath: layout.directory(for: "org/model").path))
        #expect(await manager.manifest(repoID: "org/model") == nil)
    }
}
