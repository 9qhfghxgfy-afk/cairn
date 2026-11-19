import XCTest
@testable import CairnChatDomain

/// Which knobs a client may set, and which ones are deliberately not mapped because they would
/// mean something different to the engine behind this surface.
final class ShareTurnSamplingTests: XCTestCase {

    private func turn(_ text: String, endpoint: ShareEndpoint) -> ShareTurnRequest {
        switch ShareTurnDecoder.decode(body: Data(text.utf8), endpoint: endpoint) {
        case .success(let value): return value
        case .failure(let failure): XCTFail("\(failure)") ; return ShareTurnRequest(modelID: "", messages: [], streams: false, endpoint: endpoint)
        }
    }

    func testOllamaNestsItsKnobsUnderOptionsAndTheyLandInTheSamplingConfig() {
        let body = """
            {"model":"m","prompt":"hello",
             "options":{"temperature":0.4,"top_p":0.9,"top_k":40,"min_p":0.05,"num_predict":128,
                        "repeat_penalty":1.1,"repeat_last_n":64,"seed":7,"num_ctx":4096}}
            """
        let sampling = turn(body, endpoint: .generate).sampling
        XCTAssertEqual(sampling.temperature, 0.4)
        XCTAssertEqual(sampling.topP, 0.9)
        XCTAssertEqual(sampling.topK, 40)
        XCTAssertEqual(sampling.minP, 0.05)
        XCTAssertEqual(sampling.maxTokens, 128, "num_predict is this dialect's max tokens")
        XCTAssertEqual(sampling.repeatPenalty, 1.1)
        XCTAssertEqual(sampling.repeatLastN, 64)
        XCTAssertEqual(sampling.seed, .fixed(7))
        XCTAssertEqual(sampling.contextWindow, 4096)
    }

    func testTheOpenAIShapePutsItsKnobsAtTheTopLevel() {
        let body = #"{"model":"m","messages":[{"role":"user","content":"x"}],"temperature":0.2,"top_p":0.8,"max_tokens":64,"seed":3}"#
        let sampling = turn(body, endpoint: .chat(dialect: .openAI)).sampling
        XCTAssertEqual(sampling.temperature, 0.2)
        XCTAssertEqual(sampling.topP, 0.8)
        XCTAssertEqual(sampling.maxTokens, 64)
        XCTAssertEqual(sampling.seed, .fixed(3))
    }

    /// `max_completion_tokens` is what newer clients send for the same knob. Reading only the older
    /// name would silently ignore what the caller asked for.
    func testNewerNamesForTheSameKnobAreBothHonoured() {
        let sampling = turn(#"{"model":"m","messages":[{"role":"user","content":"x"}],"max_completion_tokens":32}"#,
                            endpoint: .chat(dialect: .openAI)).sampling
        XCTAssertEqual(sampling.maxTokens, 32)
    }

    /// The two dialects' penalty knobs are not the same knob. Mapping one onto the other would send
    /// the engine a number the user never set.
    func testAKnobThatMeansSomethingElseHereIsIgnoredRatherThanMapped() {
        let sampling = turn(
            #"{"model":"m","messages":[{"role":"user","content":"x"}],"frequency_penalty":0.9,"presence_penalty":0.5}"#,
            endpoint: .chat(dialect: .openAI)
        ).sampling
        XCTAssertNil(sampling.repeatPenalty)
        XCTAssertNil(sampling.repeatLastN)
    }

    /// A client's number is the client's own: it arrives as the `fixed` mode, never as Cairn's
    /// "choose one for me" mode, and Ollama's `-1` re-roll sentinel is not passed through.
    func testASeedIsTakenAsTheClientsOwnAndNotAsCairnsChoice() {
        XCTAssertEqual(turn(#"{"model":"m","prompt":"p","options":{"seed":7}}"#, endpoint: .generate).sampling.seed, .fixed(7))
        XCTAssertNil(turn(#"{"model":"m","prompt":"p","options":{"seed":-1}}"#, endpoint: .generate).sampling.seed,
                     "a re-roll sentinel would make a served turn unreplayable")
        XCTAssertNil(turn(#"{"model":"m","prompt":"p"}"#, endpoint: .generate).sampling.seed)
    }

    /// Knobs that were not sent stay unset, so the engine's own defaults survive a client that says
    /// nothing rather than being replaced by numbers this app invented.
    func testAKnobThatWasNotSentStaysUnset() {
        let sampling = turn(#"{"model":"m","prompt":"p"}"#, endpoint: .generate).sampling
        XCTAssertNil(sampling.temperature)
        XCTAssertNil(sampling.maxTokens)
        XCTAssertNil(sampling.contextWindow)
    }
}
