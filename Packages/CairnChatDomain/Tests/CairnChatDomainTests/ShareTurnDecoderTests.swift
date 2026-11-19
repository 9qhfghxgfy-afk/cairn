import XCTest
@testable import CairnChatDomain

/// Reading a turn a client sent, in either dialect. The defaults chosen here are behaviour, not
/// decoration: they are what a client that says nothing gets.
final class ShareTurnDecoderTests: XCTestCase {

    private func turn(_ text: String, endpoint: ShareEndpoint = .chat(dialect: .ollama)) throws -> ShareTurnRequest {
        switch ShareTurnDecoder.decode(body: Data(text.utf8), endpoint: endpoint) {
        case .success(let value): return value
        case .failure(let failure): throw failure
        }
    }

    private func failure(_ text: String, endpoint: ShareEndpoint = .chat(dialect: .ollama)) -> ShareRequestFailure {
        switch ShareTurnDecoder.decode(body: Data(text.utf8), endpoint: endpoint) {
        case .success: return .undecodable
        case .failure(let value): return value
        }
    }

    func testAChatTurnInOllamasShapeIsReadWhole() throws {
        let body = """
            {"model":"cairn-foundation","messages":[{"role":"system","content":"be brief"},
             {"role":"user","content":"hi"},{"role":"assistant","content":"hello"},{"role":"user","content":"again"}],
             "stream":true,"keep_alive":"30s"}
            """
        let value = try turn(body)
        XCTAssertEqual(value.modelID, "cairn-foundation", "the served name is the engine id")
        XCTAssertEqual(value.messages.count, 4, "the conversation is forwarded as the client sent it")
        XCTAssertEqual(value.messages.first?.role, .system)
        XCTAssertEqual(value.messages.last?.text, "again")
        XCTAssertTrue(value.streams)
        XCTAssertEqual(value.endpoint, .chat(dialect: .ollama))
    }

    /// **Ollama streams unless told not to; OpenAI does not stream unless told to.** Getting this
    /// backwards looks like a broken model, because the client is left reading a body written in
    /// the other mode.
    func testTheStreamDefaultFollowsTheDialectNotTheAbsenceOfAField() throws {
        let plain = #"{"model":"m","messages":[{"role":"user","content":"hi"}]}"#
        XCTAssertTrue(try turn(plain).streams)
        XCTAssertFalse(try turn(plain, endpoint: .chat(dialect: .openAI)).streams)
        XCTAssertTrue(try turn(#"{"model":"m","messages":[{"role":"user","content":"hi"}],"stream":true}"#,
                               endpoint: .chat(dialect: .openAI)).streams)
        XCTAssertFalse(try turn(#"{"model":"m","messages":[{"role":"user","content":"hi"}],"stream":false}"#).streams)
    }

    func testTheOpenAIContentPartsAreJoinedRatherThanDropped() throws {
        let body = """
            {"model":"m","messages":[{"role":"user","content":[{"type":"text","text":"part one"},
             {"type":"text","text":" and two"}]}],"stream":false}
            """
        let value = try turn(body, endpoint: .chat(dialect: .openAI))
        XCTAssertEqual(value.messages.count, 1)
        XCTAssertEqual(value.messages.first?.text, "part one and two")
        XCTAssertFalse(value.streams)
    }

    /// A role this app does not have — `developer`, `tool`, anything — arrives as a user line
    /// rather than being dropped: the words the client sent still reach the model, and dropping
    /// them would answer a shorter question than the one that was asked.
    func testARoleThisAppDoesNotHaveArrivesAsAUserLine() throws {
        let value = try turn(
            #"{"model":"m","messages":[{"role":"developer","content":"be terse"},{"role":"user","content":"hi"}]}"#,
            endpoint: .chat(dialect: .openAI)
        )
        XCTAssertEqual(value.messages.count, 2)
        XCTAssertEqual(value.messages.first?.role, .user)
    }

    /// The completion-shaped endpoints carry one prompt instead of a message list.
    func testAPromptBodyBecomesOneUserTurn() throws {
        let value = try turn(#"{"model":"m","prompt":"finish this"}"#, endpoint: .generate)
        XCTAssertEqual(value.messages.count, 1)
        XCTAssertEqual(value.messages.first?.role, .user)
        XCTAssertEqual(value.messages.first?.text, "finish this")
        XCTAssertTrue(value.streams, "Ollama's generate streams unless told not to")
        let legacy = try turn(#"{"model":"m","prompt":"finish this"}"#, endpoint: .completion)
        XCTAssertFalse(legacy.streams, "the legacy OpenAI completion follows the OpenAI default")
    }

    func testABodyThatIsNotATurnIsRefusedWithTheReasonThatIsTrue() {
        XCTAssertEqual(failure("not json"), .undecodable, "bytes that are not JSON are not a turn")
        XCTAssertEqual(failure("[]"), .undecodable)
        XCTAssertEqual(failure(#"{"messages":[{"role":"user","content":"hi"}]}"#), .missingModel,
                       "no model named means no engine selected")
        XCTAssertEqual(failure("{}"), .missingModel)
        XCTAssertEqual(failure(#"{"model":"","messages":[{"role":"user","content":"hi"}]}"#), .missingModel,
                       "an empty name is no name")
        XCTAssertEqual(failure(#"{"model":"m","messages":[]}"#), .emptyMessages,
                       "an empty conversation is refused, not answered empty")
        XCTAssertEqual(failure(#"{"model":"m"}"#, endpoint: .completion), .emptyMessages)
    }

    /// The request handed to the engine carries no persona, no tools and no context injection: a
    /// shared surface forwards a turn, it does not arm a stranger's conversation with this phone's
    /// tools, and it does not answer a question Cairn was never asked.
    func testAGeneratedRequestCarriesNeitherToolsNorCairnsOwnContext() throws {
        let value = try turn(#"{"model":"m","messages":[{"role":"user","content":"hi"}],"options":{"temperature":0.5}}"#)
        let request = value.generationRequest()
        XCTAssertEqual(request.modelID, "m")
        XCTAssertEqual(request.messages.count, 1)
        XCTAssertTrue(request.tools.isEmpty)
        XCTAssertEqual(request.config.persona, "")
        XCTAssertEqual(request.config.sampling.temperature, 0.5)
        XCTAssertFalse(request.config.thinkingEnabled, "nothing was asked for, so nothing is asked of the engine")
    }

    func testARequestForReasoningIsReadInItsOwnDialectsWords() throws {
        let plain = #"{"model":"m","messages":[{"role":"user","content":"x"}]}"#
        XCTAssertFalse(try turn(plain).thinkingRequested)
        XCTAssertTrue(try turn(#"{"model":"m","messages":[{"role":"user","content":"x"}],"options":{"thinking":true}}"#).thinkingRequested)
        XCTAssertTrue(try turn(#"{"model":"m","messages":[{"role":"user","content":"x"}],"reasoning_effort":"high"}"#,
                               endpoint: .chat(dialect: .openAI)).thinkingRequested)
        XCTAssertFalse(try turn(#"{"model":"m","messages":[{"role":"user","content":"x"}],"reasoning_effort":"none"}"#,
                                endpoint: .chat(dialect: .openAI)).thinkingRequested)
    }
}
