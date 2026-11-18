import Foundation
import XCTest
import CairnChatDomain
@testable import CairnProviderRemote

/// The OpenAI dialect never says a call has finished: the id and name arrive in one chunk and the
/// arguments are split across the ones after it. The stitcher turns those fragments into the calls the
/// loop runs, so its promises are that a call is emitted once, in the order the model wrote it, and
/// that an argument blob with no name attached becomes nothing rather than a tool never asked for.
final class ToolCallStitcherTests: XCTestCase {

    /// Fragments decoded from SSE payloads, fed through the stitcher exactly as the pipeline feeds it.
    private func stitch(_ payloads: [String]) throws -> [ToolCallRequest] {
        var stitcher = RemoteToolCallStitcher()
        for payload in payloads {
            for event in try OpenAICodec.decodeSSEPayload(payload) {
                if case .toolCallDelta(let index, let id, let name, let arguments) = event {
                    stitcher.feed(index: index, id: id, name: name, arguments: arguments)
                }
            }
        }
        return stitcher.flush()
    }

    private func query(in call: ToolCallRequest) -> String? {
        JSONValue.decode(from: call.argumentsJSON)?.dictionaryValue?["query"]?.coercedText
    }

    /// Two calls split across chunks come back as two whole calls, in the order each first appeared,
    /// with their arguments rejoined. A reply that stopped in order to call a tool stopped on purpose.
    func testFragmentsAcrossChunksStitchIntoCallsInTheOrderTheyStarted() throws {
        let calls = try stitch([
            #"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call-1","function":{"name":"web_search","arguments":"{\"query\":\"rain in"}}]}}]}"#,
            #"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":" Paris\"}"}}]}}]}"#,
            #"{"choices":[{"delta":{"tool_calls":[{"index":1,"id":"call-2","function":{"name":"calculator","arguments":"{}"}}]}}]}"#,
        ])
        XCTAssertEqual(calls.map(\.name), [BuiltInTool.webSearch, BuiltInTool.calculator])
        XCTAssertEqual(calls.map(\.id), ["call-1", "call-2"])
        XCTAssertEqual(query(in: calls[0]), "rain in Paris", "the blob rejoined across two chunks")
        XCTAssertEqual(calls[1].argumentsJSON, "{}")
        let ending = try OpenAICodec.decodeSSEPayload(
            #"{"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#
        )
        XCTAssertEqual(ending, [.finished(.stop)], "a tool stop is a stop, not an unknown reason")
    }

    /// Many servers leave the id off every fragment but the first, so the key is the dialect's own
    /// index; a continuation with neither id nor name still joins the call it continues.
    func testAContinuationWithNoIdStillJoinsItsOwnCall() throws {
        let calls = try stitch([
            #"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call-3","function":{"name":"wiki_search"}}]}}]}"#,
            #"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"query\":\"rain\"}"}}]}}]}"#,
        ])
        XCTAssertEqual(calls.count, 1, "one call, not two")
        XCTAssertEqual(calls.first?.id, "call-3")
        XCTAssertEqual(calls.first?.name, BuiltInTool.wikiSearch)
        XCTAssertEqual(calls.first.flatMap(query), "rain")
    }

    /// Arguments with nothing to run are not a call. Guessing a name here would execute a tool the
    /// model never asked for, so the fragment is dropped and the turn goes on without it.
    func testAFragmentWithNoNameIsDroppedRatherThanGuessed() throws {
        let calls = try stitch([
            #"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"query\":\"rain\"}"}}]}}]}"#,
        ])
        XCTAssertTrue(calls.isEmpty, "no name means no call")
    }

    /// A flush hands the calls over and clears them, so a finish reason and then the end of the stream
    /// cannot each emit the same call — which would run one tool twice.
    func testAFlushCannotEmitTheSameCallTwice() throws {
        var stitcher = RemoteToolCallStitcher()
        stitcher.feed(index: 0, id: "call-4", name: BuiltInTool.calculator, arguments: #"{"expression":"2+2"}"#)
        XCTAssertEqual(stitcher.flush().count, 1)
        XCTAssertTrue(stitcher.isEmpty)
        XCTAssertTrue(stitcher.flush().isEmpty, "the second flush has nothing left to hand over")
    }
}
