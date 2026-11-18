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
        guard case .toolCall(let request)? = events[index] else {
            return try XCTUnwrap(nil, "no call at \(index): \(events)")
        }
        return request
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
        let line = Data(
            #"{"model":"qwen3:8b","message":{"role":"assistant","content":"Let me look.","tool_calls":"#
            + #"[{"id":"call-1","function":{"name":"web_search","arguments":{"query":"rain"}}}]}}"#.utf8
        )
        let events = try OllamaCodec.decodeNDJSONLine(line)
        XCTAssertEqual(events.first, .content("Let me look."))
        let request = try call(in: events)
        XCTAssertEqual(request.id, "call-1")
        XCTAssertEqual(request.name, BuiltInTool.webSearch)
        XCTAssertEqual(arguments(request.argumentsJSON), "rain")
    }

    /// Both spellings of `arguments` are in the wild: the documented object, and the string some builds
    /// emit. A missing id is filled rather than dropped, a fragment with no name is dropped rather than
    /// guessed at, and the finished chunk keeps the counts the server reported.
    func testOllamaReadsBothArgumentSpellingsAndSkipsACallWithNoName() throws {
        let blob = try XCTUnwrap(
            String(data: JSONSerialization.data(withJSONObject: ["query": "rain"]), encoding: .utf8)
        )
        let json = #"{"message":{"role":"assistant","tool_calls":[{"function":{"name":"wiki_search","arguments":#
            + stringForm(blob)
            + #"},{"function":{"arguments":"{}"}}]},"done":true,"done_reason":"stop","eval_count":12}"#
        let events = try OllamaCodec.decodeNDJSONLine(Data(json.utf8))
        let calls = events.compactMap { event -> ToolCallRequest? in
            if case .toolCall(let request) = event { return request }
            return nil
        }
        XCTAssertEqual(calls.count, 1, "a fragment with no name is not a call")
        XCTAssertEqual(calls.first?.id, "ollama-call-1", "a missing id is filled, not dropped")
        XCTAssertEqual(calls.first?.name, BuiltInTool.wikiSearch)
        XCTAssertEqual(arguments(try XCTUnwrap(calls.first?.argumentsJSON)), "rain")
        XCTAssertEqual(
            events.last,
            .finished(OllamaCodec.FinalInfo(evalCount: 12, doneReason: "stop")),
            "the counts the server reported survive the call line"
        )
    }

    /// A JSON blob the way a server writes it inside a JSON **string** value: quoted, with its own
    /// quotes escaped. The second published spelling of `arguments`.
    private func stringForm(_ blob: String) -> String {
        #"""# + blob.replacingOccurrences(of: #"""#, with: #"\""#) + #"""#
    }
}
