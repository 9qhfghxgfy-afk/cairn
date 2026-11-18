import XCTest
import SwiftData
import CairnChatDomain
@testable import CairnPersistence

/// P3 persistence: what one turn's tool use keeps, and what a row from before P3 still means.
///
/// A tool call belongs to the answer it fed, so it lives on the **one** assistant node rather than as
/// its own nodes — and what has to survive is the audit trail: what the turn was offered, what it
/// called, the arguments, the output, the measured duration and the typed failure. "The model used a
/// tool" is only checkable if the record also says what it could have used. These run in the Xcode
/// target because SwiftData needs a real runtime.
@MainActor
final class ToolRunPersistenceTests: XCTestCase {

    private func thread(_ store: SwiftDataStore, _ title: String) throws -> Conversation {
        try store.createConversation(title: title, mode: .remoteOnly, config: .default, isTemporary: false)
    }

    private var turn: ToolRun {
        var run = ToolRun(protocolUsed: .native, stepsUsed: 2, stoppedAtStepLimit: false)
        run.record(
            ToolInvocation(
                id: "call-1", name: BuiltInTool.webSearch, argumentsText: #"{"query":"rain in Paris"}"#,
                output: "3 results.", durationSeconds: 0.42, truncated: true, state: .complete,
                startedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
        run.record(
            ToolInvocation(
                id: "call-2", name: BuiltInTool.webFetch, argumentsText: #"{"url":"https://example.com"}"#,
                error: .blockedTarget, detail: "The target is on the local network.",
                durationSeconds: 0.01, state: .failed,
                startedAt: Date(timeIntervalSince1970: 1_700_000_001)
            )
        )
        return run
    }

    /// Names, arguments, outputs, durations, truncation and the typed failure all survive, in order, on
    /// the one node — and the run still says it reached the public internet, which is what keeps the
    /// outbound badge on after a reload.
    func testAToolRunAndWhatTheTurnWasOfferedSurviveTheRoundTrip() throws {
        let store = try SwiftDataStore(inMemory: true)
        let chat = try thread(store, "Weather")
        try store.saveNode(
            ChatNode(
                conversationID: chat.id, parentID: nil, role: .assistant, text: "Rain, 11 degrees.",
                providerID: "ollama", modelID: "qwen3:8b",
                toolsOffered: [BuiltInTool.webSearch, BuiltInTool.webFetch, BuiltInTool.calculator],
                toolRun: turn
            )
        )

        let stored = try XCTUnwrap(try store.nodes(conversationID: chat.id).first)
        XCTAssertEqual(stored.toolsOffered, [BuiltInTool.webSearch, BuiltInTool.webFetch, BuiltInTool.calculator])
        let run = try XCTUnwrap(stored.toolRun)
        XCTAssertEqual(run.protocolUsed, .native, "the record says the call was native, not parsed")
        XCTAssertEqual(run.callCount, 2, "one row in, one row out — no call became a second node")
        XCTAssertEqual(run.stepsUsed, 2)
        XCTAssertFalse(run.stoppedAtStepLimit)
        XCTAssertEqual(run.invocations.map(\.name), [BuiltInTool.webSearch, BuiltInTool.webFetch])
        XCTAssertEqual(run.invocations[0].argumentsText, #"{"query":"rain in Paris"}"#)
        XCTAssertEqual(run.invocations[0].output, "3 results.")
        XCTAssertEqual(run.invocations[0].durationSeconds ?? 0, 0.42, accuracy: 0.0001)
        XCTAssertTrue(run.invocations[0].truncated, "a clipped output stays marked as clipped")
        XCTAssertEqual(run.invocations[0].state, .complete)
        XCTAssertTrue(run.usedWebTools, "the badge outlives the reload")
        XCTAssertFalse(run.isStillRunning)
    }

    /// A refused call stays refused in the record: the typed reason, the detail that explains it, and
    /// its place among the calls that did work. A run that lost its failures would read as a turn where
    /// everything the model asked for happened.
    func testARefusedCallKeepsItsTypedReasonAndItsPlaceInTheRun() throws {
        let store = try SwiftDataStore(inMemory: true)
        let chat = try thread(store, "Blocked")
        try store.saveNode(
            ChatNode(conversationID: chat.id, parentID: nil, role: .assistant, text: "One way, one refused.", toolRun: turn)
        )

        let run = try XCTUnwrap(try store.nodes(conversationID: chat.id).first?.toolRun)
        let refused = try XCTUnwrap(run.invocation(id: "call-2"))
        XCTAssertEqual(refused.error, .blockedTarget)
        XCTAssertEqual(refused.detail, "The target is on the local network.")
        XCTAssertEqual(refused.state, .failed)
        XCTAssertFalse(refused.succeeded)
        XCTAssertTrue(refused.output.isEmpty, "a call that never ran has no output to show")
        XCTAssertEqual(run.failedCount, 1, "one of two calls failed, and the card says so")
        XCTAssertEqual(run.invocations.last?.name, BuiltInTool.webFetch, "the order the calls happened in")
    }

    /// A turn that used no tools writes no tool blob at all: not an empty run and not an empty offered
    /// list, both of which a later read would render as a card claiming a turn that never happened.
    func testAPlainTurnWritesNoToolBlobAtAll() throws {
        let store = try SwiftDataStore(inMemory: true)
        let chat = try thread(store, "Plain")
        try store.saveNode(
            ChatNode(conversationID: chat.id, parentID: nil, role: .assistant, text: "No tools here.")
        )

        let record = try XCTUnwrap(store.context.fetch(FetchDescriptor<ChatRecord>()).first)
        XCTAssertNil(record.toolRunJSON, "no run, so no blob")
        XCTAssertNil(record.toolsOfferedJSON, "nothing offered, so no empty array to claim otherwise")

        let stored = try XCTUnwrap(try store.nodes(conversationID: chat.id).first)
        XCTAssertNil(stored.toolRun)
        XCTAssertTrue(stored.toolsOffered.isEmpty)
    }
}
