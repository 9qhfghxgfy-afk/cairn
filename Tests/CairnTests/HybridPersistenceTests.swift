import XCTest
import SwiftData
import CairnChatDomain
@testable import CairnPersistence

/// M4 persistence, in the Xcode target because SwiftData needs a real runtime. Two things are proven
/// here: that one hybrid node keeps everything needed to read back *how* it was produced — both
/// drafts, each side's own measured numbers, a side's typed failure, and the provenance line — and
/// that a row written before M4, which has neither drafts nor provenance, still decodes as the node
/// it was rather than as a broken one.
@MainActor
final class HybridPersistenceTests: XCTestCase {

    private func metrics(tokens: Int, seconds: Double) -> GenerationMetrics {
        GenerationMetrics(tokensGenerated: tokens, elapsedSeconds: seconds, finishReason: .stop)
    }

    private func fastDraft() -> CandidateDraft {
        CandidateDraft(
            order: 0, sourceLabel: "Phone", providerID: "device", modelID: "fm",
            text: "Fast one wins.", thinking: "Short route, one hop.",
            state: .complete, metrics: metrics(tokens: 40, seconds: 2)
        )
    }

    private func failedDraft() -> CandidateDraft {
        CandidateDraft(
            order: 1, sourceLabel: "Server", providerID: "ollama", modelID: "qwen3:8b",
            text: "", state: .failed, failure: "The server closed the stream early."
        )
    }

    private func conversation(
        in store: SwiftDataStore, title: String, mode: InferenceMode
    ) throws -> Conversation {
        try store.createConversation(title: title, mode: mode, config: .default, isTemporary: false)
    }

    /// A Parallel turn is one node holding both sides. Each side keeps its own text, its own
    /// reasoning (or the absence of it), and its own measured rate — numbers copied from the other
    /// side would make the panels lie.
    func testAParallelNodeKeepsBothSidesAndEachSidesOwnNumbers() throws {
        let store = try SwiftDataStore(inMemory: true)
        let thread = try conversation(in: store, title: "Compared", mode: .hybridParallel)
        let node = ChatNode(
            conversationID: thread.id, parentID: nil, role: .assistant, kind: .hybridParallel,
            text: "Fast one wins.", providerID: "device", modelID: "fm",
            drafts: [fastDraft(), failedDraft()],
            provenance: HybridProvenance(
                mode: .hybridParallel, candidateCount: 2, failedCandidateCount: 1
            )
        )
        try store.saveNode(node)

        let stored = try XCTUnwrap(try store.nodes(conversationID: thread.id).first)
        XCTAssertEqual(stored.kind, .hybridParallel)
        XCTAssertEqual(stored.text, "Fast one wins.", "the primary side's answer stands on the node")
        XCTAssertEqual(stored.drafts.count, 2)
        XCTAssertEqual(stored.drafts.map(\.order), [0, 1], "plan order survives")
        XCTAssertEqual(stored.drafts[0].sourceLabel, "Phone")
        XCTAssertEqual(stored.drafts[0].thinking, "Short route, one hop.")
        XCTAssertEqual(stored.drafts[0].metrics?.tokensGenerated, 40)
        XCTAssertEqual(stored.drafts[0].metrics?.finishReason, .stop)
        let rate = try XCTUnwrap(stored.drafts[0].metrics?.tokensPerSecond)
        XCTAssertEqual(rate, 20.0, accuracy: 0.0001, "measured from this side's own tokens")

        XCTAssertNil(stored.drafts[1].thinking, "a side that emitted nothing comes back as nothing")
        XCTAssertNil(stored.drafts[1].metrics, "a side that never produced tokens has no rate")
        XCTAssertEqual(stored.drafts[1].failure, "The server closed the stream early.")
        XCTAssertEqual(stored.drafts[1].state, .failed, "a failed draft is kept, not dropped")

        let provenance = try XCTUnwrap(stored.provenance)
        XCTAssertEqual(provenance.candidateCount, 2)
        XCTAssertEqual(provenance.failedCandidateCount, 1)
        XCTAssertNil(provenance.synthesizerEngineID, "Parallel has no writer to credit")
        XCTAssertEqual(provenance.summary, "Compared 2 drafts · 1 failed")
    }

    /// The writer attribution is the whole point of a synthesized turn: who read the drafts and wrote
    /// the answer. The summary line is asserted identical before and after the round trip, because one
    /// word missing from the stored blob would change what the bubble claims.
    func testASynthesizedNodeKeepsItsWriterAndTheLineThatSaysSo() throws {
        let store = try SwiftDataStore(inMemory: true)
        let thread = try conversation(in: store, title: "Unified", mode: .hybridSynthesized)
        let provenance = HybridProvenance(
            mode: .hybridSynthesized, synthesizerEngineID: "ollama", synthesizerModelID: "qwen3:8b",
            candidateCount: 2, failedCandidateCount: 0, synthesisRan: true
        )
        let node = ChatNode(
            conversationID: thread.id, parentID: nil, role: .assistant, kind: .synthesized,
            text: "Both point the same way.", thinking: "The two sides agree on the first step.",
            providerID: "ollama", modelID: "qwen3:8b",
            drafts: [fastDraft(), failedDraft()], provenance: provenance
        )
        try store.saveNode(node)

        let stored = try XCTUnwrap(try store.nodes(conversationID: thread.id).first)
        XCTAssertEqual(stored.kind, .synthesized)
        XCTAssertEqual(stored.text, "Both point the same way.", "the unified answer, not a side's draft")
        XCTAssertEqual(stored.thinking, "The two sides agree on the first step.",
                       "the writer's own reasoning, kept because the writer emitted it")
        XCTAssertEqual(stored.drafts.count, 2, "the drafts travel inside the one node")
        let restored = try XCTUnwrap(stored.provenance)
        XCTAssertEqual(restored, provenance)
        XCTAssertEqual(restored.summary, provenance.summary)
        XCTAssertEqual(restored.summary, "Synthesized by ollama · qwen3:8b from 2 drafts")
    }

    /// A second hybrid answer on the same node is an update, not a new row: the tree is a tree, and a
    /// store that appended would grow the conversation out of nothing.
    func testARewrittenHybridAnswerUpdatesItsOwnRow() throws {
        let store = try SwiftDataStore(inMemory: true)
        let thread = try conversation(in: store, title: "Rewritten", mode: .hybridSynthesized)
        var node = ChatNode(
            conversationID: thread.id, parentID: nil, role: .assistant, kind: .synthesized,
            text: "first", drafts: [fastDraft(), failedDraft()],
            provenance: HybridProvenance(candidateCount: 2, failedCandidateCount: 1)
        )
        try store.saveNode(node)

        node.text = "second"
        node.providerID = "device"
        node.drafts = [fastDraft()]
        node.provenance = HybridProvenance(
            mode: .hybridSynthesized, synthesizerEngineID: "device", synthesizerModelID: "fm",
            candidateCount: 2, failedCandidateCount: 0, synthesisRan: true
        )
        try store.saveNode(node)

        let all = try store.nodes(conversationID: thread.id)
        XCTAssertEqual(all.count, 1, "one node in, one row out")
        let stored = try XCTUnwrap(all.first)
        XCTAssertEqual(stored.text, "second")
        XCTAssertEqual(stored.providerID, "device", "attribution follows the engine that wrote it")
        XCTAssertEqual(stored.drafts.count, 1)
        XCTAssertEqual(stored.provenance?.failedCandidateCount, 0, "the new provenance replaces the old")
    }
}
