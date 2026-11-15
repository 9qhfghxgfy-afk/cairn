import XCTest
@testable import CairnChatDomain

/// Milestone 1 gate: streaming and cancellation behaviour against the mock engine and
/// the memory-only store, with no networking involved.
@MainActor
final class ChatSessionStreamingTests: XCTestCase {

    func testSendAppendsUserThenAssistantAndStreamsContent() async throws {
        let (model, store) = try SessionHarness.makeSession()
        await model.bootstrap()
        XCTAssertTrue(model.path.isEmpty)

        model.send("Explain cairns")
        await SessionHarness.settle(model)

        XCTAssertEqual(model.path.map(\.role), [.user, .assistant])
        let assistant = model.path.last
        XCTAssertEqual(assistant?.role, .assistant)
        XCTAssertFalse(assistant?.text.isEmpty ?? true, "content should have streamed in")
        XCTAssertEqual(assistant?.state, .complete)
        XCTAssertNotNil(assistant?.metrics, "the mock emits real .metrics, so they must be recorded")
        XCTAssertGreaterThan(assistant?.metrics?.tokensGenerated ?? 0, 0)

        // Persisted, not merely view state.
        let stored = try store.nodes(conversationID: model.conversation.id)
        XCTAssertEqual(stored.count, 2)
        XCTAssertEqual(model.conversation.activeLeafID, assistant?.id)
        XCTAssertEqual(model.conversation.title, "Explain cairns")
    }

    func testReasoningPanelAppearsOnlyWhenTheProviderEmitsThinking() async throws {
        let (withThinking, _) = try SessionHarness.makeSession(thinkingEnabled: true)
        await withThinking.bootstrap()
        withThinking.send("think about this")
        await SessionHarness.settle(withThinking)
        XCTAssertNotNil(withThinking.path.last?.thinking)
        XCTAssertFalse(withThinking.path.last?.thinking?.isEmpty ?? true)

        let (silent, _) = try SessionHarness.makeSession(thinkingEnabled: false)
        await silent.bootstrap()
        silent.send("no reasoning please")
        await SessionHarness.settle(silent)
        XCTAssertNil(silent.path.last?.thinking, "no thinking chunks means no reasoning panel")
        XCTAssertFalse(silent.accumulator.hasReasoning)
    }

    func testCancellationKeepsPartialTextAndMarksNodeCancelled() async throws {
        let slow = MockStreamingProvider(thinkingCapable: false, tokenDelayNanoseconds: 40_000_000)
        let (model, store) = try SessionHarness.makeSession(provider: slow, thinkingEnabled: false)
        await model.bootstrap()

        model.send("count slowly")
        await SessionHarness.awaitSomeContent(model)
        XCTAssertFalse(model.accumulator.text.isEmpty, "expected streamed text before cancelling")

        model.cancelStreaming()
        await SessionHarness.settle(model)

        let assistant = model.path.last
        XCTAssertEqual(assistant?.state, .cancelled)
        XCTAssertFalse(assistant?.text.isEmpty ?? true, "cancel must not throw away generated text")

        let stored = try store.nodes(conversationID: model.conversation.id)
        XCTAssertEqual(
            stored.first(where: { $0.role == .assistant })?.state, .cancelled,
            "partial output is persisted incrementally, not only at the end"
        )
    }

    func testMidStreamFailureKeepsPartialOutputAndReportsTheFailure() async throws {
        let flaky = MockStreamingProvider(tokenDelayNanoseconds: 0, failAfterTokens: 3)
        let (model, _) = try SessionHarness.makeSession(provider: flaky, thinkingEnabled: false)
        await model.bootstrap()

        model.send("fail partway")
        await SessionHarness.settle(model)

        XCTAssertEqual(model.accumulator.phase, .failed)
        XCTAssertEqual(model.path.last?.state, .failed)
        XCTAssertFalse(model.accumulator.text.isEmpty)
        XCTAssertNotNil(model.accumulator.failure)
    }

    func testSendIsIgnoredWhileATurnIsInFlight() async throws {
        let slow = MockStreamingProvider(thinkingCapable: false, tokenDelayNanoseconds: 60_000_000)
        let (model, _) = try SessionHarness.makeSession(provider: slow, thinkingEnabled: false)
        await model.bootstrap()

        model.send("first")
        XCTAssertTrue(model.isBusy)
        model.send("second while busy")
        XCTAssertEqual(model.nodes.filter { $0.role == .user }.count, 1,
                       "a second send while streaming must not create a stray node")
        model.cancelStreaming()
        await SessionHarness.settle(model)
    }

    func testModelListingFeedsTheSelector() async throws {
        let (model, _) = try SessionHarness.makeSession()
        await model.bootstrap()
        XCTAssertFalse(model.availableModels.isEmpty)
        XCTAssertFalse(model.selectedModelID.isEmpty, "a default model must be chosen for a fresh chat")
        XCTAssertEqual(model.activeProvider?.networkClass, .onDevice)
        XCTAssertTrue(model.activeProvider?.capabilities.thinking ?? false)
    }
}
