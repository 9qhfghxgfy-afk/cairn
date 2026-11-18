import XCTest
import SwiftData
import CairnChatDomain
@testable import CairnPersistence

/// What a store written before M4 does when it meets the M4 reader, read from both ends of the
/// column. The upgrade has to be additive in both directions: an old row gains nothing it never had
/// (no drafts, no provenance, no hybrid plan), and a plain node's columns stay empty rather than
/// storing an empty struct that would read later as a claim about a turn that never happened.
@MainActor
final class HybridLegacyRowTests: XCTestCase {

    private func conversation(
        in store: SwiftDataStore, title: String, mode: InferenceMode
    ) throws -> Conversation {
        try store.createConversation(title: title, mode: mode, config: .default, isTemporary: false)
    }

    /// A row written before M4 has no provenance column and no drafts column. It must read back as the
    /// plain node it is — nils, not an empty struct pretending to be provenance.
    func testAPreM4NodeRowReadsWithNoDraftsAndNoProvenance() throws {
        let store = try SwiftDataStore(inMemory: true)
        let thread = try conversation(in: store, title: "Old thread", mode: .hybridSynthesized)
        let legacy = ChatRecord(
            id: UUID(), conversationID: thread.id, parentID: nil, roleRaw: "assistant",
            kindRaw: "plain", stateRaw: "complete", text: "An answer from before M4.",
            thinking: nil, branchIndex: 0, providerID: "device", modelID: "fm",
            createdAt: Date(timeIntervalSince1970: 5), draftsJSON: nil, metricsJSON: nil
        )
        store.context.insert(legacy)
        try store.context.save()

        let stored = try XCTUnwrap(try store.nodes(conversationID: thread.id).first)
        XCTAssertEqual(stored.kind, .plain)
        XCTAssertEqual(stored.text, "An answer from before M4.")
        XCTAssertTrue(stored.drafts.isEmpty)
        XCTAssertNil(stored.provenance)
        XCTAssertNil(stored.metrics)
    }

    /// The other direction: a hybrid node writes both blobs, a plain node writes neither. `nil` stays
    /// `nil` instead of a stored `null` blob or an empty array.
    func testAPlainNodeWritesNoDraftsAndNoProvenanceBlob() throws {
        let store = try SwiftDataStore(inMemory: true)
        let thread = try conversation(in: store, title: "Plain", mode: .remoteOnly)
        try store.saveNode(
            ChatNode(conversationID: thread.id, parentID: nil, role: .assistant, text: "One answer.")
        )
        let record = try XCTUnwrap(store.context.fetch(FetchDescriptor<ChatRecord>()).first)
        XCTAssertNil(record.draftsJSON)
        XCTAssertNil(record.provenanceJSON)
    }

    /// A chat configured before M4 has a configuration blob with no `hybrid` key in it. It still
    /// decodes, keeps every knob it had, and reports no stored plan — which is what makes the session
    /// choose a plan from the engines that exist now instead of inventing one.
    func testAPreM4ConfigurationBlobReadsWithNoStoredPlan() throws {
        let store = try SwiftDataStore(inMemory: true)
        var modern = ChatConfig.default
        modern.persona = "Be terse."
        modern.hybrid = HybridPlan(
            candidates: [
                HybridCandidate(engineID: "device", modelID: "fm"),
                HybridCandidate(engineID: "ollama", modelID: "qwen3:8b"),
            ]
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(modern)) as? [String: Any]
        )
        object.removeValue(forKey: "hybrid")  // exactly what a pre-M4 build wrote
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let id = UUID()
        store.context.insert(
            ConversationRecord(
                id: id, title: "Old chat", activeLeafID: nil,
                createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2),
                modeRaw: "hybridSynthesized", paramsJSON: Data(), configJSON: legacy
            )
        )
        try store.context.save()

        let upgraded = try XCTUnwrap(try store.conversation(id: id))
        XCTAssertNil(upgraded.config.hybrid, "nothing was chosen, so nothing is claimed")
        XCTAssertEqual(upgraded.config.persona, "Be terse.", "the knobs it did have survive")
        XCTAssertEqual(upgraded.mode, .hybridSynthesized)
    }
}
