import XCTest
@testable import CairnChatDomain

/// The candidate stage of a hybrid turn: sides run together when they may, never both resident
/// when they may not, and a side that fails keeps what it said instead of vanishing.
final class HybridEngineTests: XCTestCase {

    func testBothSidesAnswerAndGenuinelyOverlap() async throws {
        let ledger = HybridLedger()
        let remote = ScriptedProvider(id: "lan", name: "LAN server", networkClass: .privateLan, tokenDelay: 4_000_000, overlapTarget: 2, ledger: ledger)
        let cloud = ScriptedProvider(id: "cloud", name: "Cloud server", networkClass: .publicInternet, fragments: ["other ", "answer"], tokenDelay: 4_000_000, overlapTarget: 2, ledger: ledger)
        let job = HybridTestSupport.job(
            mode: .hybridParallel,
            pairs: [("lan", "server-a"), ("cloud", "cloud-a")],
            providers: [remote, cloud],
            classes: [.privateLan, .publicInternet]
        )

        let events = try await HybridTestSupport.drain(job)
        let result = try HybridTestSupport.outcome(of: events)
        let reading = await ledger.snapshot()

        XCTAssertEqual(reading.peakLive, 2, "a concurrent group must actually run both sides at once")
        XCTAssertEqual(result.drafts.map(\.order), [0, 1])
        XCTAssertTrue(result.drafts.allSatisfy(\.answered))
        XCTAssertEqual(result.state, .complete)
        XCTAssertEqual(result.primaryText, result.drafts[0].text, "parallel turns stand the primary side's answer")
        XCTAssertNil(result.synthesis, "parallel mode writes no unified answer")
        XCTAssertEqual(result.provenance.mode, .hybridParallel)
        XCTAssertFalse(result.provenance.synthesisRan)
    }

    func testTwoOnDeviceSidesAreNeverResidentTogetherAndAreReleasedBetween() async throws {
        let ledger = HybridLedger()
        let first = ScriptedProvider(id: "local-a", name: "Model A", networkClass: .onDevice, tokenDelay: 6_000_000, ledger: ledger)
        let second = ScriptedProvider(id: "local-b", name: "Model B", networkClass: .onDevice, fragments: ["b1 ", "b2"], tokenDelay: 6_000_000, ledger: ledger)
        let job = HybridTestSupport.job(
            mode: .hybridParallel,
            pairs: [("local-a", "8b"), ("local-b", "3b")],
            providers: [first, second],
            classes: [.onDevice, .onDevice],
            residency: SpyResidencyGate(ledger: ledger)
        )

        _ = try await HybridTestSupport.drain(job)
        let reading = await ledger.snapshot()

        XCTAssertEqual(reading.peakLiveOnDevice, 1, "two on-device models were resident at once")
        XCTAssertEqual(reading.peakLive, 1)
        XCTAssertEqual(reading.evictions, 1, "the release between sequential on-device runs must be real")
    }

    func testOnDeviceSidesRunTogetherOnlyWhenTheGateReportsRoom() async throws {
        let ledger = HybridLedger()
        let first = ScriptedProvider(id: "local-a", name: "Model A", networkClass: .onDevice, tokenDelay: 4_000_000, overlapTarget: 2, ledger: ledger)
        let second = ScriptedProvider(id: "local-b", name: "Model B", networkClass: .onDevice, fragments: ["b1 ", "b2"], tokenDelay: 4_000_000, overlapTarget: 2, ledger: ledger)
        let job = HybridTestSupport.job(
            mode: .hybridParallel,
            pairs: [("local-a", "8b"), ("local-b", "3b")],
            providers: [first, second],
            classes: [.onDevice, .onDevice],
            residency: SpyResidencyGate(ledger: ledger, allowsTwo: true)
        )

        _ = try await HybridTestSupport.drain(job)
        let reading = await ledger.snapshot()

        XCTAssertEqual(reading.peakLiveOnDevice, 2, "a measured reading said there was room for both")
        XCTAssertEqual(reading.evictions, 0, "nothing was released, so nothing should have been evicted")
    }

    func testAFailedSideKeepsItsReasonWhileTheSurvivingSideAnswers() async throws {
        let broken = ScriptedProvider(
            id: "lan",
            name: "LAN server",
            networkClass: .privateLan,
            fragments: ["partial ", "words "],
            failureMessage: "The server closed the socket mid-answer."
        )
        let sound = ScriptedProvider(id: "cloud", name: "Cloud server", networkClass: .publicInternet, fragments: ["a real ", "answer"])
        let job = HybridTestSupport.job(
            mode: .hybridParallel,
            pairs: [("lan", "server-a"), ("cloud", "cloud-a")],
            providers: [broken, sound],
            classes: [.privateLan, .publicInternet]
        )

        let events = try await HybridTestSupport.drain(job)
        let result = try HybridTestSupport.outcome(of: events)

        XCTAssertEqual(result.drafts.count, 2)
        XCTAssertEqual(result.drafts[0].failure, "The server closed the socket mid-answer.")
        XCTAssertEqual(result.drafts[0].text, "partial words ", "a failed side keeps what it managed to say")
        XCTAssertEqual(result.state, .complete)
        XCTAssertEqual(result.primaryText, result.drafts[1].text, "the surviving side stands in when the primary side fails")
        XCTAssertEqual(result.provenance.failedCandidateCount, 1)
        XCTAssertTrue(result.provenance.summary.contains("1 failed"))
    }

    func testEverySideFailingEndsFailedWithoutInventingAnAnswer() async throws {
        let brokenA = ScriptedProvider(id: "lan", name: "LAN server", networkClass: .privateLan, fragments: [], failureMessage: "No route to host.")
        let brokenB = ScriptedProvider(id: "cloud", name: "Cloud server", networkClass: .publicInternet, fragments: [], failureMessage: "Rate limited by the server.")
        let job = HybridTestSupport.job(
            mode: .hybridParallel,
            pairs: [("lan", "server-a"), ("cloud", "cloud-a")],
            providers: [brokenA, brokenB],
            classes: [.privateLan, .publicInternet]
        )

        let events = try await HybridTestSupport.drain(job)
        let result = try HybridTestSupport.outcome(of: events)

        XCTAssertEqual(result.state, .failed)
        XCTAssertEqual(result.primaryText, "", "nothing was said, so nothing may be stored as an answer")
        XCTAssertEqual(result.provenance.failedCandidateCount, 2)
        XCTAssertEqual(result.drafts.compactMap(\.failure), ["No route to host.", "Rate limited by the server."])
    }

    func testDraftsStayInPlanOrderHoweverFastEachSideIs() async throws {
        let slow = ScriptedProvider(id: "lan", name: "LAN server", networkClass: .privateLan, tokenDelay: 25_000_000)
        let fast = ScriptedProvider(id: "cloud", name: "Cloud server", networkClass: .publicInternet, fragments: ["quick"])
        let job = HybridTestSupport.job(
            mode: .hybridParallel,
            pairs: [("lan", "server-a"), ("cloud", "cloud-a")],
            providers: [slow, fast],
            classes: [.privateLan, .publicInternet]
        )

        let events = try await HybridTestSupport.drain(job)
        let result = try HybridTestSupport.outcome(of: events)

        XCTAssertEqual(result.drafts.map(\.order), [0, 1], "the panels must not reshuffle as sides land")
        XCTAssertEqual(result.drafts.map(\.providerID), ["lan", "cloud"])
        XCTAssertNotNil(result.drafts[0].metrics, "a side's own metrics come from its own stream")
    }
}