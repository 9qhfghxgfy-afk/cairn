import XCTest
@testable import CairnChatDomain

/// M4 at the session level: a hybrid turn runs several engines and still writes **one** assistant
/// node, whose text, drafts, provenance and attribution all come from the same outcome — so they
/// cannot disagree, and a stop or a refusal never rewrites the tree.
@MainActor
final class ChatSessionHybridTests: XCTestCase {

    private func makeSession(
        mode: InferenceMode,
        providers: [any InferenceProvider],
        plan: HybridPlan?
    ) throws -> (ChatSessionModel, EphemeralStore) {
        let store = EphemeralStore()
        let conversation = try store.createConversation(
            title: "Hybrid chat",
            mode: mode,
            config: ChatConfig(hybrid: plan),
            isTemporary: true
        )
        return (ChatSessionModel(conversation: conversation, store: store, providers: providers), store)
    }

    private func awaitDraftContent(_ model: ChatSessionModel, maxTicks: Int = 200) async {
        var ticks = 0
        while model.path.last?.drafts.contains(where: { !$0.text.isEmpty }) != true, ticks < maxTicks {
            ticks += 1
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testAParallelTurnWritesOneAssistantNodeCarryingBothDrafts() async throws {
        let server = ScriptedProvider(id: "lan", name: "LAN server", networkClass: .privateLan, fragments: ["server ", "answer"])
        let phone = MockStreamingProvider(id: "local", thinkingCapable: false, tokenDelayNanoseconds: 2_000_000)
        let (model, store) = try makeSession(
            mode: .hybridParallel,
            providers: [server, phone],
            plan: HybridPlan(candidates: [
                HybridCandidate(engineID: "lan", modelID: "server-a"),
                HybridCandidate(engineID: "local", modelID: "cairn-mock-8b"),
            ])
        )
        await model.bootstrap()

        model.send("What is a cairn?")
        await SessionHarness.settle(model)

        XCTAssertEqual(model.path.map(\.role), [.user, .assistant], "one turn, one assistant node")
        let node = try XCTUnwrap(model.path.last)
        XCTAssertEqual(node.kind, .hybridParallel)
        XCTAssertEqual(node.drafts.map(\.order), [0, 1])
        XCTAssertEqual(node.drafts.map(\.providerID), ["lan", "local"])
        XCTAssertEqual(node.text, "server answer", "the primary side's answer stands as the node's text")
        XCTAssertEqual(node.state, .complete)
        XCTAssertEqual(node.provenance?.mode, .hybridParallel)
        XCTAssertEqual(node.provenance?.candidateCount, 2)
        XCTAssertEqual(model.hybrid?.stage, .finished)
        XCTAssertNil(node.provenance?.synthesizerEngineID, "parallel mode has no writer to credit")

        let stored = try store.nodes(conversationID: model.conversation.id)
        let storedAssistant = try XCTUnwrap(stored.last(where: { $0.role == .assistant }))
        XCTAssertEqual(storedAssistant.drafts.count, 2, "the drafts are persisted, not just view state")
        XCTAssertEqual(storedAssistant.provenance?.candidateCount, 2)
    }

    func testASynthesizedTurnHandsTheNodeToTheEngineThatWroteIt() async throws {
        let server = ScriptedProvider(id: "lan", name: "LAN server", networkClass: .privateLan, fragments: ["server side"])
        let phone = MockStreamingProvider(id: "local", thinkingCapable: false, tokenDelayNanoseconds: 0)
        let writer = ScriptedProvider(id: "writer", name: "Writer", networkClass: .privateLan, fragments: ["one unified ", "answer"])
        let (model, _) = try makeSession(
            mode: .hybridSynthesized,
            providers: [server, phone, writer],
            plan: HybridPlan(
                candidates: [
                    HybridCandidate(engineID: "lan", modelID: "server-a"),
                    HybridCandidate(engineID: "local", modelID: "cairn-mock-8b"),
                ],
                synthesizer: HybridCandidate(engineID: "writer", modelID: "writer-model")
            )
        )
        await model.bootstrap()

        model.send("What is a cairn?")
        await SessionHarness.settle(model)

        let node = try XCTUnwrap(model.path.last)
        XCTAssertEqual(node.kind, .synthesized)
        XCTAssertEqual(node.text, "one unified answer")
        XCTAssertEqual(node.providerID, "writer", "the node is credited to the engine that wrote its text")
        XCTAssertEqual(node.modelID, "writer-model")
        XCTAssertEqual(node.provenance?.synthesizerEngineID, "writer")
        XCTAssertEqual(node.provenance?.synthesisRan, true)
        XCTAssertEqual(node.state, .complete)
        XCTAssertEqual(node.drafts.count, 2, "the drafts travel with the unified answer")
    }

    func testAHybridTurnRefusesToStartWithOneSideAndSaysWhy() async throws {
        let server = ScriptedProvider(id: "lan", name: "LAN server", networkClass: .privateLan)
        let (model, _) = try makeSession(mode: .hybridSynthesized, providers: [server], plan: nil)
        await model.bootstrap()

        model.send("What is a cairn?")
        await SessionHarness.settle(model)

        XCTAssertTrue(
            model.lastError?.contains("two candidates") ?? false,
            "the refusal must name what is missing, got: \(model.lastError ?? "nil")"
        )
        let node = try XCTUnwrap(model.path.last)
        XCTAssertEqual(node.state, .failed)
        XCTAssertEqual(node.text, "")
        XCTAssertTrue(node.drafts.isEmpty, "nothing ran, so nothing may be shown as an answer")
    }

    func testStoppingAHybridTurnKeepsWhatAlreadyLanded() async throws {
        let slowA = ScriptedProvider(id: "lan", name: "LAN server", networkClass: .privateLan, fragments: ["one ", "two ", "three ", "four "], tokenDelay: 40_000_000)
        let slowB = ScriptedProvider(id: "local", name: "Phone", networkClass: .onDevice, fragments: ["five ", "six ", "seven "], tokenDelay: 40_000_000)
        let (model, store) = try makeSession(
            mode: .hybridParallel,
            providers: [slowA, slowB],
            plan: HybridPlan(candidates: [
                HybridCandidate(engineID: "lan", modelID: "server-a"),
                HybridCandidate(engineID: "local", modelID: "phone-model"),
            ])
        )
        await model.bootstrap()

        model.send("count slowly")
        await awaitDraftContent(model)
        model.cancelStreaming()
        await SessionHarness.settle(model)

        let node = try XCTUnwrap(model.path.last)
        XCTAssertNotEqual(node.state, .complete, "a stopped turn may not be stored as finished")
        XCTAssertTrue(node.drafts.contains(where: { !$0.text.isEmpty }), "what each side already said survives")
        let stored = try store.nodes(conversationID: model.conversation.id)
        XCTAssertEqual(stored.last(where: { $0.role == .assistant })?.drafts.count, 2, "the partial drafts are on disk too")
    }

    func testRegeneratingAHybridTurnAppendsASiblingAndKeepsTheFirstAnswer() async throws {
        let server = ScriptedProvider(id: "lan", name: "LAN server", networkClass: .privateLan, fragments: ["first ", "answer"])
        let phone = ScriptedProvider(id: "local", name: "Phone", networkClass: .onDevice, fragments: ["other ", "answer"])
        let (model, _) = try makeSession(
            mode: .hybridParallel,
            providers: [server, phone],
            plan: HybridPlan(candidates: [
                HybridCandidate(engineID: "lan", modelID: "server-a"),
                HybridCandidate(engineID: "local", modelID: "phone-model"),
            ])
        )
        await model.bootstrap()

        model.send("What is a cairn?")
        await SessionHarness.settle(model)
        let first = try XCTUnwrap(model.path.last)

        model.regenerate(assistantNodeID: first.id)
        await SessionHarness.settle(model)

        let second = try XCTUnwrap(model.path.last)
        XCTAssertNotEqual(second.id, first.id)
        XCTAssertEqual(second.parentID, first.parentID, "a regeneration is a sibling, never a rewrite")
        XCTAssertGreaterThanOrEqual(second.branchIndex, 1)
        XCTAssertTrue(model.nodes.contains(where: { $0.id == first.id }), "the first answer is still in the tree")
        XCTAssertEqual(second.drafts.count, 2, "a regenerated hybrid turn ran both sides again")
    }
}