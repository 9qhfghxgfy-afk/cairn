import XCTest
import CairnPersistence
@testable import CairnChatDomain
import CairnInferenceLocal

/// That the injected gate actually reaches the turn — the part a pure unit test cannot show, because
/// the whole point of the seam is that the app layer hands the answer down. A session built by a
/// workspace with no gate must keep the domain's strict default; a session built by one with a gate must
/// answer with that exact gate, and a chat reopened later must not silently lose it.
@MainActor
final class HybridResidencyInjectionTests: XCTestCase {

    private func workspace(engineIDs: [String]) throws -> ChatWorkspace {
        ChatWorkspace(
            persistentStore: try SwiftDataStore(inMemory: true),
            providers: engineIDs.map { MockStreamingProvider(id: $0) as any InferenceProvider }
        )
    }

    /// Unwired is not unguarded. Every session that nobody has handed a gate answers "one on-device
    /// model at a time", which is the rule that keeps a half-wired build from overflowing the ceiling.
    func testAnUnwiredSessionKeepsTheStrictDefaultGate() throws {
        let workspace = try workspace(engineIDs: ["device"])
        workspace.startNewChat()
        let gate = try XCTUnwrap(workspace.session?.residency)
        XCTAssertTrue(gate is NeverTwoOnDeviceResident)
        XCTAssertFalse(gate.allowsTwoOnDeviceModelsResident())
    }

    /// The gate is passed by identity, not copied into a wrapper: the workspace's registry, the gate's
    /// registry and the release a turn performs have to be the same object or eviction unloads nothing.
    func testTheWorkspaceHandsItsOwnGateToEverySessionItBuilds() throws {
        let spy = SpyResidencyGate(allowsTwoOnDeviceModelsResident: true)
        let workspace = try workspace(engineIDs: ["device", "server"])
        workspace.residency = spy
        workspace.startNewChat()

        let handed = try XCTUnwrap(workspace.session?.residency as? SpyResidencyGate)
        XCTAssertTrue(handed === spy, "the same gate, not a look-alike")
        XCTAssertTrue(handed.allowsTwoOnDeviceModelsResident())
    }

    /// Reopening an old chat goes down a different path than starting a new one, so the gate has to be
    /// attached in the shared builder rather than remembered by whichever screen started the chat.
    func testAReopenedChatCarriesTheSameGate() throws {
        let store = try SwiftDataStore(inMemory: true)
        let existing = try store.createConversation(
            title: "Reopened", mode: .hybridParallel, config: .default, isTemporary: false
        )
        let spy = SpyResidencyGate()
        let workspace = ChatWorkspace(persistentStore: store, providers: [MockStreamingProvider(id: "device")])
        workspace.residency = spy
        workspace.select(conversationID: existing.id)

        let handed = try XCTUnwrap(workspace.session?.residency as? SpyResidencyGate)
        XCTAssertTrue(handed === spy)
        XCTAssertFalse(handed.allowsTwoOnDeviceModelsResident(), "a refusing gate stays refusing")
    }

    /// The end of the chain: the gate that reaches the session is the gate the assembled turn runs with.
    /// Everything above this line is wiring; this is the claim M4 makes.
    func testTheGateTravelsIntoTheAssembledTurn() async throws {
        let store = try SwiftDataStore(inMemory: true)
        let thread = try store.createConversation(
            title: "Wired", mode: .hybridParallel, config: .default, isTemporary: false
        )
        let session = ChatSessionModel(
            conversation: thread, store: store,
            providers: [MockStreamingProvider(id: "mock-a"), MockStreamingProvider(id: "mock-b")]
        )
        let spy = SpyResidencyGate()
        session.residency = spy

        // Both engines must be read before a plan is worth running: a candidate with no model is a
        // refusal, not a guess, so the plan only resolves once each engine's real model is known.
        await session.loadModels(forEngine: "mock-a")
        await session.loadModels(forEngine: "mock-b")
        let plan = session.hybridPlan
        XCTAssertTrue(plan.isRunnable, plan.issue?.reasonText ?? "runnable")

        let job = try XCTUnwrap(session.makeHybridJob(assistantNodeID: UUID()))
        let carried = try XCTUnwrap(job.residency as? SpyResidencyGate)
        XCTAssertTrue(carried === spy, "the turn releases through the injected registry")
        XCTAssertEqual(job.networkClasses, [.onDevice, .onDevice])
    }
}
