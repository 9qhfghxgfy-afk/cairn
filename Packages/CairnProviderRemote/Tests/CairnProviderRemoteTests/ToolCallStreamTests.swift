import Foundation
import XCTest
import CairnChatDomain
@testable import CairnProviderRemote

/// P3b wire decoding: the calls a model asked for, read back in both dialects and stitched into the
/// whole calls a turn runs.
///
/// The two dialects disagree on purpose — Ollama answers with one complete structured call, OpenAI
/// splits one call across chunks with the arguments in pieces — so the stitching is what the loop is
/// actually handed, and the order it produces is the order the cards show.
final class ToolCallStreamTests: XCTestCase {

    private func arguments(_ json: String) -> String? {
        JSONValue.decode(from: json)?.dictionaryValue?["query"]?.coercedText
    }

    private func call(in events: [OllamaCodec.Event], at index: Int = 1) throws -> ToolCallRequest {
        guard case .toolCall(let request) = events[index] else {
            return try XCTUnwrap(nil, "no call at \(index): \(events)")
        }
        return request
    }

    /// One NDJSON line, built by the serialiser rather than written by hand. The fixtures here are
    /// nested three levels deep and one of them carries a JSON blob inside a JSON string; a hand-typed
    /// version of that is a quoting trap that fails in the fixture rather than in the decoder, which is
    /// the worst possible place for a test to be wrong.
    private func ndjsonLine(_ message: [String: Any], done: Bool = false, evalCount: Int? = nil) throws -> Data {
        var payload: [String: Any] = ["model": "qwen3:8b", "message": message]
        if done {
            payload["done"] = true
            payload["done_reason"] = "stop"
        }
        if let evalCount { payload["eval_count"] = evalCount }
        return try XCTUnwrap(JSONSerialization.data(withJSONObject: payload))
    }

    // MARK: - Calls going back out

    /// The same call, in the two shapes the two servers document. An object where a string is expected
    /// is how a strict server refuses a whole turn, and the empty blob still has to be a valid value.
    func testAnAssistantCallSendsAnObjectToOllamaAndAStringToOpenAI() throws {
        let call = ToolCallRequest(
            id: "call-9", name: BuiltInTool.webSearch, argumentsJSON: #"{"query":"rain in Paris"}"#
        )
        let turn = GenerationRequest(
            modelID: "qwen3:8b",
            messages: [
                ChatMessagePayload(role: .user, text: "Weather?"),
                ChatMessagePayload(role: .assistant, text: "", toolCalls: [call]),
                ChatMessagePayload.toolResult(callID: "call-9", text: "Rain, 11 degrees."),
            ],
            config: .default, tools: [], toolProtocol: .native
        )
        let ollamaMessages = try XCTUnwrap(
            (try JSONSerialization.jsonObject(
                with: OllamaCodec.chatRequestBody(turn, support: .all)
            ) as? [String: Any])?["messages"] as? [[String: Any]]
        )
        let openAIMessages = try XCTUnwrap(
            (try JSONSerialization.jsonObject(
                with: OpenAICodec.chatRequestBody(turn, support: .all)
            ) as? [String: Any])?["messages"] as? [[String: Any]]
        )
        XCTAssertEqual(ollamaMessages.count, 3)
        XCTAssertEqual(openAIMessages.count, 3)

        let ollama = ollamaMessages[1]
        let openAI = openAIMessages[1]
        let ollamaResult = ollamaMessages[2]
        let openAIResult = openAIMessages[2]

        let ollamaCall = try XCTUnwrap((ollama["tool_calls"] as? [[String: Any]])?.first)
        let ollamaFunction = try XCTUnwrap(ollamaCall["function"] as? [String: Any])
        let openAICall = try XCTUnwrap((openAI["tool_calls"] as? [[String: Any]])?.first)
        let openAIFunction = try XCTUnwrap(openAICall["function"] as? [String: Any])
        XCTAssertTrue(
            ollamaFunction["arguments"] is [String: Any],
            "Ollama publishes arguments as an object"
        )
        XCTAssertTrue(
            openAIFunction["arguments"] is String,
            "OpenAI publishes arguments as a JSON string"
        )
        XCTAssertEqual(ollamaCall["id"] as? String, "call-9")
        XCTAssertEqual(openAICall["id"] as? String, "call-9")
        XCTAssertEqual(openAICall["type"] as? String, "function")
        XCTAssertEqual(arguments(try XCTUnwrap(openAIFunction["arguments"] as? String)), "rain in Paris")
        // The result that answers the call keeps its id in both dialects, so the pairing survives.
        XCTAssertEqual(ollamaResult["tool_call_id"] as? String, "call-9")
        XCTAssertEqual(openAIResult["tool_call_id"] as? String, "call-9")
    }

    // MARK: - Calls coming back

    /// A model that says "let me look" and then calls a tool says the sentence first, and the loop has
    /// to see the text before it runs anything. This dialect answers with one complete call per line.
    func testOllamaReadsAWholeStructuredCallAfterTheSentenceThatIntroducedIt() throws {
        let line = try ndjsonLine([
            "role": "assistant",
            "content": "Let me look.",
            "tool_calls": [
                ["id": "call-1", "function": ["name": BuiltInTool.webSearch, "arguments": ["query": "rain"]]],
            ],
        ])
        let events = try OllamaCodec.decodeNDJSONLine(line)
        XCTAssertEqual(events.first, .content("Let me look."), "the sentence arrives before the call")
        let request = try call(in: events)
        XCTAssertEqual(request.id, "call-1")
        XCTAssertEqual(request.name, BuiltInTool.webSearch)
        XCTAssertEqual(arguments(request.argumentsJSON), "rain")
    }

    /// Both spellings of `arguments` are in the wild: the documented object, and the same blob inside a
    /// JSON string, which is what some builds emit. A missing id is filled rather than dropped, a
    /// fragment with no name is dropped rather than guessed at, and the finished chunk keeps the counts.
    func testOllamaReadsBothArgumentSpellingsAndSkipsACallWithNoName() throws {
        let blob = try XCTUnwrap(
            String(data: JSONSerialization.data(withJSONObject: ["query": "rain"]), encoding: .utf8)
        )
        let line = try ndjsonLine(
            [
                "role": "assistant",
                "tool_calls": [
                    ["function": ["name": BuiltInTool.wikiSearch, "arguments": blob]],
                    ["function": ["arguments": "{}"]],
                ],
            ],
            done: true, evalCount: 12
        )
        let events = try OllamaCodec.decodeNDJSONLine(line)
        let calls = events.compactMap { event -> ToolCallRequest? in
            if case .toolCall(let request) = event { return request }
            return nil
        }
        XCTAssertEqual(calls.count, 1, "a fragment with no name is not a call")
        XCTAssertEqual(calls.first?.id, "ollama-call-1", "a missing id is filled, not dropped")
        XCTAssertEqual(calls.first?.name, BuiltInTool.wikiSearch)
        XCTAssertEqual(calls.first.flatMap { arguments($0.argumentsJSON) }, "rain", "unwrapped from a string")
        XCTAssertEqual(
            events.last,
            .finished(OllamaCodec.FinalInfo(evalCount: 12, doneReason: "stop")),
            "the counts the server reported survive the call line"
        )
    }
}
