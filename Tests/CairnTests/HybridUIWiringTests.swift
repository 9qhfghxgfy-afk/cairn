import XCTest
import CairnChatDomain
import CairnPersistence
@testable import CairnAppUI

/// The rules the hybrid UI runs on. The pixels belong to the views; what is pinned here is what they
/// promise: the live panel appears only for a hybrid turn really in flight, the two candidate rows
/// behave the way the plan requires, a half-built plan says why it cannot run instead of failing on the
/// next send, and a reasoning panel appears only for a side that actually emitted reasoning.
@MainActor
final class HybridUIWiringTests: XCTestCase {

    private let phone = HybridCandidate(engineID: "device", modelID: "fm")
    private let server = HybridCandidate(engineID: "ollama", modelID: "qwen3:8b")

    /// A session keeps its last hybrid snapshot standing after the turn ends so the panels can still be
    /// read, so the panel has to be gated on the mode and the turn — not on the snapshot existing. A
    /// finished hybrid turn must not keep animating in the header of a chat that moved on to a plain one.
    func testTheLivePanelNeedsAHybridModeAndATurnNotJustASnapshot() {
        XCTAssertTrue(HybridPanelRule.showsPanel(mode: .hybridParallel, isBusy: true, hasSnapshot: true))
        XCTAssertTrue(HybridPanelRule.showsPanel(mode: .hybridSynthesized, isBusy: true, hasSnapshot: true))
        XCTAssertFalse(HybridPanelRule.showsPanel(mode: .hybridParallel, isBusy: false, hasSnapshot: true),
                       "a finished turn stops animating")
        XCTAssertFalse(HybridPanelRule.showsPanel(mode: .remoteOnly, isBusy: true, hasSnapshot: true),
                       "a plain turn never shows a stale hybrid panel")
        XCTAssertFalse(HybridPanelRule.showsPanel(mode: .onDeviceOnly, isBusy: false, hasSnapshot: false))
    }

    /// Both rows exist before anything is chosen, and a plan with one row filled is reported as
    /// half-built rather than run. Sending a half-chosen name is how a server gets a model it does not
    /// have, which is the failure this screen exists to prevent.
    func testTwoRowsAlwaysExistAndBothHaveToBeFilled() {
        let empty = HybridPlan()
        XCTAssertFalse(empty.isRunnable)
        XCTAssertEqual(HybridPlanSlots.slot(empty, at: 1).engineID, "", "a second row is there to fill in")

        var plan = HybridPlanSlots.setting(empty, engineAt: 0, to: "device", model: "fm")
        XCTAssertEqual(HybridPlanSlots.slot(plan, at: 0).modelID, "fm")
        XCTAssertEqual(plan.issue, .incompleteCandidate, "one row is a half-built plan, not a runnable one")

        plan = HybridPlanSlots.setting(plan, engineAt: 1, to: "ollama", model: "qwen3:8b")
        XCTAssertTrue(plan.isRunnable)
        XCTAssertEqual(plan.candidates.map(\.id), ["device|fm", "ollama|qwen3:8b"], "declared order is kept")
    }

    /// Choosing an engine re-resolves its model, and only that row's. Carrying a model name across
    /// engines is exactly the mistake the picker must not make.
    func testAnEngineSwapDropsTheModelThatBelongedToTheOldEngine() {
        let plan = HybridPlan(candidates: [phone, server])
        let swapped = HybridPlanSlots.setting(plan, engineAt: 0, to: "server", model: "")
        XCTAssertEqual(HybridPlanSlots.slot(swapped, at: 0).modelID, "", "nothing is carried across engines")
        XCTAssertEqual(HybridPlanSlots.slot(swapped, at: 1).modelID, "qwen3:8b", "the other row is untouched")
    }

    /// The writer picker may only offer a side that is really in the plan, and "let Cairn choose" is a
    /// real state — empty means remote first, which is the rule the turn resolves with.
    func testTheWriterTagRoundTripsAndClearsBackToChoosing() {
        let plan = HybridPlan(candidates: [phone, server])
        XCTAssertEqual(HybridPlanSlots.synthesizerTag(of: plan), "", "no tag means Cairn chooses")

        let tagged = HybridPlanSlots.setting(plan, synthesizerTag: "device|fm")
        XCTAssertEqual(HybridPlanSlots.synthesizerTag(of: tagged), "device|fm")
        XCTAssertEqual(tagged.synthesizer?.modelID, "fm")

        let stray = HybridPlanSlots.setting(plan, synthesizerTag: "somewhere|else")
        XCTAssertNil(stray.synthesizer, "a side that is not in the plan is not a writer")
        XCTAssertEqual(HybridPlanSlots.synthesizerTag(of: stray), "")

        let doubled = HybridPlan(candidates: [phone, phone])
        XCTAssertEqual(HybridPlanSlots.chosen(doubled).count, 1, "a picker cannot show the same side twice")
        XCTAssertEqual(doubled.issue, .duplicateCandidate, "the plan still reports the duplicate")
    }

    /// A chat in a hybrid mode with every engine's real models read — the state a chat is in after the
    /// configuration sheet or `bootstrap()` has run, and the only state a hybrid plan is built from.
    private func wiredWorkspace(
        mode: InferenceMode, engineIDs: [String]
    ) async throws -> ChatWorkspace {
        let workspace = ChatWorkspace(
            persistentStore: try SwiftDataStore(inMemory: true),
            providers: engineIDs.map { MockStreamingProvider(id: $0) as any InferenceProvider }
        )
        workspace.startNewChat()
        workspace.mode = mode
        for id in engineIDs { await workspace.session?.loadModels(forEngine: id) }
        return workspace
    }

    /// The mode a user chose owes them the reason it cannot run, said in the header rather than left to
    /// fail on the next send — and from the same plan the sheet shows and the turn refuses with. One
    /// rule, three readers, and no screen with its own opinion about readiness.
    func testAHybridChatWithOneEngineSaysWhyItCannotRun() throws {
        let workspace = ChatWorkspace(
            persistentStore: try SwiftDataStore(inMemory: true),
            providers: [MockStreamingProvider(id: "device")]
        )
        workspace.startNewChat()
        workspace.mode = .hybridParallel
        XCTAssertEqual(
            ChatScreen(workspace: workspace).hybridRefusal,
            HybridPlanIssue.needsTwoCandidates.reasonText
        )
    }

    /// Once both engines have been read, the same chat reads as runnable and the header stops warning.
    /// Nothing is promised before an engine's real model is known.
    func testAHybridChatWithTwoReadableEnginesReadsAsRunnable() async throws {
        let workspace = try await wiredWorkspace(
            mode: .hybridSynthesized, engineIDs: ["mock-a", "mock-b"]
        )
        let session = try XCTUnwrap(workspace.session)
        XCTAssertTrue(session.hybridPlan.isRunnable, session.hybridPlan.issue?.reasonText ?? "runnable")
        XCTAssertNil(ChatScreen(workspace: workspace).hybridRefusal)
    }

    /// A plain chat never carries a hybrid warning, even the one a hybrid chat would show: a chat that
    /// is not in a hybrid mode has nothing to explain.
    func testAPlainChatCarriesNoHybridWarning() async throws {
        let workspace = try await wiredWorkspace(mode: .remoteOnly, engineIDs: ["mock-a"])
        XCTAssertNotNil(workspace.session)
        XCTAssertNil(ChatScreen(workspace: workspace).hybridRefusal)
    }

    /// An engine the app can see is named in its own words; one it cannot see right now is named by its
    /// id. Inventing a name for a server nobody has registered is how a row ends up promising an answer
    /// nothing will give.
    func testAnEngineIsNamedByItsOwnWordsOrNotAtAll() async throws {
        let workspace = try await wiredWorkspace(mode: .hybridParallel, engineIDs: ["device"])
        let session = try XCTUnwrap(workspace.session)
        XCTAssertEqual(session.engineDisplayName("device"), "Mock Engine (on-device)")
        XCTAssertEqual(session.engineDisplayName("gone-server"), "gone-server")
    }

    /// Which name the bubble carries: a synthesized node is named for the engine that wrote it, a
    /// compared node for the comparison, and nothing else gets a hybrid word.
    func testTheRowNamesWhatProducedTheAnswer() async throws {
        let workspace = try await wiredWorkspace(mode: .hybridSynthesized, engineIDs: ["mock-a"])
        let session = try XCTUnwrap(workspace.session)
        let conversationID = session.conversation.id
        func title(_ role: ChatRole, _ kind: NodeKind) -> String {
            MessageRow(session: session, node: ChatNode(
                conversationID: conversationID, parentID: nil, role: role, kind: kind, text: "x"
            )).roleTitle
        }
        XCTAssertEqual(title(.user, .plain), "You")
        XCTAssertEqual(title(.assistant, .plain), "Cairn")
        XCTAssertEqual(title(.assistant, .synthesized), "Synthesized")
        XCTAssertEqual(title(.assistant, .hybridParallel), "Compared")
    }

    /// The reasoning panel is gated on the draft's own `thinking` field, which is only ever set by a
    /// backend that emitted reasoning. An empty field is not a panel, and a side with no reasoning gets
    /// no panel — Cairn does not write a thinking display around an answer it has no reasoning for, and
    /// never borrows the other side's to fill one in.
    func testADraftCardOffersReasoningOnlyToTheSideThatEmittedIt() {
        var draft = CandidateDraft(order: 0, sourceLabel: "Phone", providerID: "device", modelID: "fm")
        XCTAssertFalse(HybridDraftCard(draft: draft).hasOwnReasoning)
        draft.thinking = ""
        XCTAssertFalse(HybridDraftCard(draft: draft).hasOwnReasoning, "an empty field is not a panel")
        draft.thinking = "One hop, then the answer."
        XCTAssertTrue(HybridDraftCard(draft: draft).hasOwnReasoning)
    }
}
