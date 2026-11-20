import Foundation
import XCTest
@testable import CairnChatDomain

/// The sentences the composer shows under the switches, and the sentence about the window.
///
/// Both exist because of the same complaint: the switches are up, and nothing visible happens. A
/// backend that has never emitted a reasoning field shows no panel, and a backend that is not given
/// a tool schema is handed its tools as text — neither is a fault, and neither is discoverable from
/// an empty panel. Proved on the session rather than in a view because the composer prints exactly
/// what these return, so a wrong string here is a wrong sentence on the screen.
@MainActor
final class EngineCapabilityNoteTests: XCTestCase {

    private func session(
        engine: any InferenceProvider,
        thinking: Bool,
        tools: Bool,
        contextWindow: Int? = nil
    ) throws -> ChatSessionModel {
        let store = EphemeralStore()
        let conversation = try store.createConversation(
            title: "Notes",
            mode: .onDeviceOnly,
            config: ChatConfig(
                sampling: SamplingConfig(contextWindow: contextWindow),
                thinkingEnabled: thinking,
                toolToggle: ToolToggleSet(isEnabled: tools)
            ),
            isTemporary: true
        )
        return ChatSessionModel(conversation: conversation, store: store, providers: [engine])
    }

    // MARK: the thinking switch

    func testASwitchForReasoningOnAnEngineThatEmitsNoneSaysSo() throws {
        let session = try session(
            engine: CapabilityStub(thinking: false), thinking: true, tools: false
        )
        let notes = session.engineCapabilityNotes
        XCTAssertEqual(notes.count, 1)
        XCTAssertTrue(notes[0].contains("Thinking"), notes[0])
        // Names the engine, because a chat can be pointed at several and a note about the wrong one
        // is worse than no note.
        XCTAssertTrue(notes[0].contains("Stub Engine"), notes[0])
    }

    func testASwitchForReasoningOnAnEngineThatEmitsItSaysNothing() throws {
        let session = try session(
            engine: CapabilityStub(thinking: true), thinking: true, tools: false
        )
        XCTAssertTrue(session.engineCapabilityNotes.isEmpty, "a promise the engine keeps is not a warning")
    }

    /// A switch nobody has thrown is not a problem worth a line of the composer.
    func testSwitchesAtRestProduceNoNoteAtAll() throws {
        let session = try session(
            engine: CapabilityStub(thinking: false), thinking: false, tools: false
        )
        XCTAssertTrue(session.engineCapabilityNotes.isEmpty)
    }

    // MARK: the tools switch

    func testToolsOnAnEngineThatCannotCallToolsSaysTheyArriveAsText() throws {
        let session = try session(
            engine: CapabilityStub(toolCalling: false), thinking: false, tools: true
        )
        let notes = session.engineCapabilityNotes
        XCTAssertEqual(notes.count, 1)
        XCTAssertTrue(notes[0].contains("text"), notes[0])
    }

    func testToolsOnAnEngineThatCanCallThemSaysNothing() throws {
        let session = try session(
            engine: CapabilityStub(toolCalling: true), thinking: false, tools: true
        )
        XCTAssertTrue(session.engineCapabilityNotes.isEmpty)
    }

    func testNoEngineSelectedSaysNothingAboutCapabilities() throws {
        let store = EphemeralStore()
        let conversation = try store.createConversation(
            title: "Bare", mode: .onDeviceOnly,
            config: ChatConfig(thinkingEnabled: true), isTemporary: true
        )
        let session = ChatSessionModel(conversation: conversation, store: store, providers: [])
        XCTAssertTrue(session.engineCapabilityNotes.isEmpty)
        XCTAssertNil(session.contextCeilingNote)
    }

    // MARK: the window

    func testAWindowTheChatAskedForThatTheEngineCannotHoldIsSaidOutLoud() throws {
        let session = try session(
            engine: CapabilityStub(ceiling: 4096), thinking: false, tools: false,
            contextWindow: 32_768
        )
        let note = try XCTUnwrap(session.contextCeilingNote)
        XCTAssertTrue(note.contains("4096"), note)
        XCTAssertTrue(note.contains("tokens"), note)
    }

    /// An unset window means "as much as you have", so a capped engine still has to say what that is.
    func testAnUnsetWindowOnACappedEngineIsStillSaid() throws {
        let session = try session(
            engine: CapabilityStub(ceiling: 4096), thinking: false, tools: false, contextWindow: nil
        )
        XCTAssertNotNil(session.contextCeilingNote)
    }

    func testAWindowTheEngineCanHoldGoesUnmentioned() throws {
        let session = try session(
            engine: CapabilityStub(ceiling: 4096), thinking: false, tools: false, contextWindow: 2048
        )
        XCTAssertNil(session.contextCeilingNote)
    }

    /// An engine that states no window is not being trimmed, so nothing is claimed about one.
    func testAnEngineThatStatesNoWindowIsNeverTrimmedOutLoud() throws {
        let session = try session(
            engine: CapabilityStub(ceiling: nil), thinking: false, tools: false, contextWindow: 32_768
        )
        XCTAssertNil(session.contextCeilingNote)
    }
}

/// An engine with only the two flags these notes read, set by hand. The mock carries thinking but
/// never tool calling and never a ceiling, and the point of these tests is the combinations the mock
/// cannot make.
private struct CapabilityStub: InferenceProvider {
    var id: String { "stub" }
    var displayName: String { "Stub Engine" }
    var networkClass: NetworkClass { .onDevice }
    var serverProfileID: UUID? { nil }

    var caps: ProviderCapabilities
    var ceiling: Int?

    init(thinking: Bool = false, toolCalling: Bool = false, ceiling: Int? = nil) {
        self.caps = ProviderCapabilities(thinking: thinking, toolCalling: toolCalling)
        self.ceiling = ceiling
    }

    var capabilities: ProviderCapabilities { caps }
    var contextTokenCeiling: Int? { ceiling }

    func models() async throws -> [ModelInfo] { [] }

    func stream(_ request: GenerationRequest) -> AsyncThrowingStream<StreamChunk, any Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

