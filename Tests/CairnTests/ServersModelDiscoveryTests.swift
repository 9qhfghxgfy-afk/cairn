import XCTest
import CairnChatDomain
@testable import CairnAppUI

/// What the Servers screen does with a local-network scan: it never starts on its own, it stops when
/// told, what it finds stays a draft until the user taps Add, and saving a finding goes through the
/// ordinary save path so a scan result cannot skip validation. `@testable` because the scan lifecycle
/// is module-internal on purpose — nothing outside this module may start a sweep of someone's LAN.
@MainActor
final class ServersModelDiscoveryTests: XCTestCase {

    private var finding: DiscoveredServer {
        DiscoveredServer(host: "192.168.1.10", port: 11434, kind: .ollama, modelCount: 4)
    }

    private func makeModel(
        scanner: (any ServerDiscovering)?
    ) -> (ServersModel, RecordingProfileStore, MemorySecretStore) {
        let store = RecordingProfileStore()
        let secrets = MemorySecretStore()
        let model = ServersModel(
            storing: store,
            testing: StubTester(),
            managing: StubModelService(),
            secrets: secrets,
            discovering: scanner,
            engineBuilder: { _ in [] }
        )
        return (model, store, secrets)
    }

    private func settled(_ model: ServersModel) async throws {
        for _ in 0..<400 where model.isScanning {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertFalse(model.isScanning, "the scan never finished")
    }

    func testNothingIsScannedUntilTheUserAsks() {
        let scanner = FakeScanner()
        let (model, _, _) = makeModel(scanner: scanner)
        XCTAssertTrue(model.discovered.isEmpty)
        XCTAssertFalse(model.isScanning)
        XCTAssertEqual(scanner.calls, 0, "a sweep never runs at launch, on a timer, or by opening the screen")
    }

    func testAUserInitiatedScanFillsTheListWithDraftsAndTouchesNothing() async throws {
        let scanner = FakeScanner()
        scanner.progressTicks = 3
        scanner.report = LANDiscoveryReport(servers: [finding], hostsScanned: 253, probesIssued: 759)
        let (model, store, secrets) = makeModel(scanner: scanner)

        model.scanLocalNetwork()
        XCTAssertTrue(model.isScanning, "the screen has to be able to say it is looking")
        try await settled(model)

        XCTAssertEqual(model.discovered.map(\.id), ["192.168.1.10:11434"])
        XCTAssertEqual(model.scanProgress?.hostsDone, 3, "progress reaches the screen")
        XCTAssertNil(model.scanHint, "a scan that found something has nothing to explain")
        XCTAssertTrue(store.saved.isEmpty, "a finding is not a saved server")
        XCTAssertTrue(secrets.items.isEmpty, "and a scan never writes a credential")
    }

    func testTwoTapsDoNotStartTwoSweeps() async throws {
        let scanner = FakeScanner()
        scanner.hangsUntilCancelled = true
        let (model, _, _) = makeModel(scanner: scanner)

        model.scanLocalNetwork()
        XCTAssertTrue(model.isScanning)
        model.scanLocalNetwork()
        // The second tap is refused synchronously; give the first sweep time to actually start, so
        // the count proves one scan rather than a second one that simply had not begun yet.
        try await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(scanner.calls, 1, "one sweep at a time, so two scans cannot race over the same /24")
        model.stopLocalNetworkScan()
        try await settled(model)
    }

    func testStoppingAScanSaysNothingWasSaved() throws {
        let scanner = FakeScanner()
        scanner.hangsUntilCancelled = true
        let (model, store, _) = makeModel(scanner: scanner)

        model.scanLocalNetwork()
        model.stopLocalNetworkScan()

        XCTAssertFalse(model.isScanning)
        XCTAssertTrue(model.discovered.isEmpty)
        XCTAssertEqual(model.scanHint, "Stopped. Nothing was saved.")
        XCTAssertTrue(store.saved.isEmpty)
    }

    func testAScanWithNoScannerIsRefusedQuietly() {
        let (model, _, _) = makeModel(scanner: nil)
        model.scanLocalNetwork()
        XCTAssertFalse(model.isScanning, "no scanner means no scan, not a spinner that never resolves")
        XCTAssertNil(model.scanHint)
    }

    func testAnEmptySweepSaysWhatItMeans() async throws {
        let scanner = FakeScanner()
        scanner.report = LANDiscoveryReport(servers: [], hostsScanned: 253, probesIssued: 759)
        let (model, _, _) = makeModel(scanner: scanner)

        model.scanLocalNetwork()
        try await settled(model)

        XCTAssertTrue(model.discovered.isEmpty)
        XCTAssertNotNil(model.scanHint, "an empty sweep explains itself instead of looking broken")
    }

    func testSavingAFindingUsesTheOrdinarySavePathAndStoresNoToken() throws {
        let (model, store, secrets) = makeModel(scanner: FakeScanner())

        model.saveDiscovery(finding)

        let stored = try XCTUnwrap(store.saved.values.first)
        XCTAssertEqual(stored.kind, .ollama)
        XCTAssertEqual(stored.baseURLString, "http://192.168.1.10:11434", "a found box is addressed over plain http")
        XCTAssertTrue(stored.enabled, "a saved server is usable straight away")
        XCTAssertFalse(stored.hasBearerToken, "a discovered server never arrives with a key")
        XCTAssertTrue(secrets.items.isEmpty, "nothing reached the Keychain")
        XCTAssertEqual(model.profiles.count, 1, "and the list shows it, because there is no second save path")
    }

    func testClearingTheFindingsTouchesNothingThatWasSaved() throws {
        let (model, store, _) = makeModel(scanner: FakeScanner())
        model.saveDiscovery(finding)
        let savedCount = store.saved.count

        model.clearDiscovery()

        XCTAssertTrue(model.discovered.isEmpty)
        XCTAssertNil(model.scanProgress)
        XCTAssertNil(model.scanHint)
        XCTAssertEqual(store.saved.count, savedCount, "clearing the screen is not an undo of a save")
    }
}
