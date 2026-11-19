import CairnChatDomain
import Foundation
import XCTest
@testable import CairnProviderRemote

/// The surface's own rules, without a socket: every refusal is a code the screen can name, and the
/// served set is fixed at the moment sharing starts.
///
/// These use a stub address source rather than the interface table, so they run wherever `Network`
/// exists without needing a network — the only bind attempted here is loopback.
@MainActor
final class ShareServerTests: XCTestCase {
    private let key = ShareToken.generate()

    private func server(
        engines: [any InferenceProvider] = [MockStreamingProvider(id: "cairn-mock", thinkingCapable: false)],
        address: String? = "127.0.0.1"
    ) -> CairnShareServer {
        CairnShareServer(engines: { engines }, addressSource: { address })
    }

    func testEveryRefusalIsReturnedAsTheCodeThatStoppedIt() async {
        // Each `start` is awaited into a name first: XCTest's assertions take autoclosures, and an
        // autoclosure does not run concurrency, so `XCTAssertEqual(await …)` does not compile.
        let noKey = server()
        let noKeyDecision = await noKey.start(port: 11_434, token: "", engineIDs: ["cairn-mock"])
        XCTAssertEqual(noKeyDecision, .refused(.needsToken))

        let weakKey = server()
        let weakKeyDecision = await weakKey.start(port: 11_434, token: "short", engineIDs: ["cairn-mock"])
        XCTAssertEqual(weakKeyDecision, .refused(.tokenTooWeak))

        let nothingTicked = server()
        let nothingTickedDecision = await nothingTicked.start(port: 11_434, token: key, engineIDs: [])
        XCTAssertEqual(nothingTickedDecision, .refused(.needsModel))

        // A name that matches no live engine is dropped rather than served as a ghost, so the request
        // to share it is a request with nothing behind it.
        let ghostName = server()
        let ghostDecision = await ghostName.start(port: 11_434, token: key, engineIDs: ["not-an-engine-here"])
        XCTAssertEqual(ghostDecision, .refused(.needsModel))

        let notLocal = server(address: "server.example.com")
        let notLocalDecision = await notLocal.start(port: 11_434, token: key, engineIDs: ["cairn-mock"])
        XCTAssertEqual(notLocalDecision, .refused(.notLocalAddress))

        let noAddress = server(address: nil)
        let noAddressDecision = await noAddress.start(port: 11_434, token: key, engineIDs: ["cairn-mock"])
        XCTAssertEqual(noAddressDecision, .refused(.noAddress))

        let badPort = server()
        let badPortDecision = await badPort.start(port: 80, token: key, engineIDs: ["cairn-mock"])
        XCTAssertEqual(badPortDecision, .refused(.portUnusable))
    }

    func testARefusedStartLeavesTheScreenAFailedStateAndTheReason() async {
        let surface = server()
        let decision = await surface.start(port: 11_434, token: "short", engineIDs: ["cairn-mock"])
        XCTAssertFalse(decision.isAllowed)
        XCTAssertEqual(surface.status.state, .failed)
        XCTAssertEqual(surface.status.failure, .tokenTooWeak)
        XCTAssertFalse(surface.status.isSharing, "a refused start must not look like a running port")
    }

    func testStartingRunsThePolicyAndReportsTheServedSetAndBoundAddress() async {
        let surface = server()
        let decision = await surface.start(port: 47_001, token: key, engineIDs: ["cairn-mock"])

        XCTAssertEqual(decision, .allowed)
        XCTAssertEqual(surface.status.state, .running)
        XCTAssertEqual(surface.status.boundAddress, "127.0.0.1")
        XCTAssertEqual(surface.status.servedModelIDs, ["cairn-mock"])
        XCTAssertFalse(surface.status.isServingTurn)

        await surface.stop()
    }

    func testASecondStartIsRefusedRatherThanStackingASecondListener() async {
        let surface = server()
        _ = await surface.start(port: 47_002, token: key, engineIDs: ["cairn-mock"])
        let again = await surface.start(port: 47_003, token: key, engineIDs: ["cairn-mock"])
        await surface.stop()

        XCTAssertEqual(again, .refused(.alreadyRunning))
    }

    func testStoppingClosesEverythingTheScreenReads() async {
        let surface = server()
        _ = await surface.start(port: 47_004, token: key, engineIDs: ["cairn-mock"])

        await surface.stop()

        XCTAssertEqual(surface.status, .off)
        XCTAssertTrue(surface.table.isEmpty, "a stopped surface holds no engine it could still answer with")
        XCTAssertEqual(surface.token, "")
    }

    func testTheListableEnginesComeFromTheLiveListNotFromASavedRecord() {
        let surface = server(engines: [
            MockStreamingProvider(id: "cairn-mock"),
            MockStreamingProvider(id: "cairn-second"),
        ])

        XCTAssertEqual(surface.availableEngines().map(\.id), ["cairn-mock", "cairn-second"])
    }
}
