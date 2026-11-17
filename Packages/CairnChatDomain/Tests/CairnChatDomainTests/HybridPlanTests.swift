import XCTest
@testable import CairnChatDomain

/// What a plan is allowed to say, what a pre-M4 chat still decodes to, and what survives a JSON
/// round trip — the shapes the store writes and reads back.
final class HybridPlanTests: XCTestCase {

    private static let remote = HybridCandidate(engineID: "lan", modelID: "server-a")
    private static let local = HybridCandidate(engineID: "local", modelID: "on-device-model")

    func testAPlanNeedsTwoSidesToBeATurnWorthRunning() {
        XCTAssertEqual(HybridPlan(candidates: [Self.remote]).issue, .needsTwoCandidates)
        XCTAssertNil(HybridPlan(candidates: [Self.remote, Self.local]).issue)
    }

    func testAHalfChosenRowIsRejectedRatherThanSent() {
        let plan = HybridPlan(candidates: [Self.remote, HybridCandidate(engineID: "local", modelID: "")])
        XCTAssertEqual(plan.issue, .incompleteCandidate)
        XCTAssertFalse(plan.isRunnable)
    }

    func testTheSameEngineAndModelTwiceIsRejected() {
        let plan = HybridPlan(candidates: [Self.remote, Self.remote])
        XCTAssertEqual(plan.issue, .duplicateCandidate)
    }

    func testTheDefaultPlanPairsARemoteSideWithAnOnDeviceSide() {
        let plan = HybridPlan.defaultPlan(from: [
            HybridEngineOption(engineID: "local", modelID: "8b", networkClass: .onDevice),
            HybridEngineOption(engineID: "lan", modelID: "server-a", networkClass: .privateLan),
        ])
        XCTAssertEqual(plan.candidates.map(\.engineID), ["lan", "local"], "the primary side is the remote one")
        XCTAssertNil(plan.synthesizer, "nil means Cairn chooses, which resolves to the remote side")
    }

    func testTheDefaultPlanTakesTheFirstTwoUsableRowsWhenNothingIsPaired() {
        let plan = HybridPlan.defaultPlan(from: [
            HybridEngineOption(engineID: "lan-a", modelID: "model-a", networkClass: .privateLan),
            HybridEngineOption(engineID: "lan-b", modelID: "model-b", networkClass: .privateLan),
            HybridEngineOption(engineID: "lan-c", modelID: "", networkClass: .privateLan),
        ])
        XCTAssertEqual(plan.candidates.map(\.id), ["lan-a|model-a", "lan-b|model-b"])
    }

    /// A chat written before M4 has no `hybrid` key at all. It must still decode, with the plan
    /// read as nil — "choose from what is registered" — rather than failing the row closed.
    func testAConfigurationWrittenBeforeM4StillDecodes() throws {
        let data = try JSONEncoder().encode(ChatConfig(persona: "be brief", hybrid: HybridPlan(candidates: [Self.remote, Self.local])))
        var blob = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        blob.removeValue(forKey: "hybrid")
        let stripped = try JSONSerialization.data(withJSONObject: blob)

        let decoded = try JSONDecoder().decode(ChatConfig.self, from: stripped)
        XCTAssertNil(decoded.hybrid)
        XCTAssertEqual(decoded.persona, "be brief")
    }

    func testProvenanceSurvivesTheJSONRoundTripTheStoreUses() throws {
        let provenance = HybridProvenance(
            mode: .hybridSynthesized,
            synthesizerEngineID: "lan",
            synthesizerModelID: "server-a",
            candidateCount: 2,
            failedCandidateCount: 1,
            synthesisRan: true
        )
        let decoded = try JSONDecoder().decode(
            HybridProvenance.self,
            from: try XCTUnwrap(JSONEncoder().encode(provenance))
        )
        XCTAssertEqual(decoded, provenance)
    }

    func testDraftMetricsAndFailureSurviveTheRoundTripAndAbsentKeysReadAsNil() throws {
        let drafts = [
            CandidateDraft(
                order: 0,
                sourceLabel: "LAN server",
                providerID: "lan",
                modelID: "server-a",
                text: "an answer",
                state: .complete,
                metrics: GenerationMetrics(tokensGenerated: 3, promptTokens: 9, elapsedSeconds: 0.4, timeToFirstTokenSeconds: 0.1, finishReason: .stop)
            ),
            CandidateDraft(
                order: 1,
                sourceLabel: "Cloud server",
                providerID: "cloud",
                modelID: "cloud-a",
                state: .failed,
                failure: "Rate limited by the server."
            ),
        ]
        let roundTripped = try JSONDecoder().decode(
            [CandidateDraft].self,
            from: try XCTUnwrap(JSONEncoder().encode(drafts))
        )
        XCTAssertEqual(roundTripped, drafts)

        // A draft row written before M4 carries neither key; both must read back as nil.
        let legacyBlob = Data(#"[{"id":"1F7C1A44-6F1B-4E37-9C1D-2C7E9B0D5C11","order":0,"sourceLabel":"LAN server","providerID":"lan","modelID":"server-a","text":"an answer","thinking":null,"state":"complete"}]"#.utf8)
        let legacy = try JSONDecoder().decode([CandidateDraft].self, from: legacyBlob)
        XCTAssertEqual(legacy.count, 1)
        XCTAssertNil(legacy.first?.metrics)
        XCTAssertNil(legacy.first?.failure)
    }
}