import Foundation
import XCTest
import CairnChatDomain
@testable import CairnProviderRemote

/// P3b wire encoding: the `tools` array a turn advertises, and the message a tool result travels in,
/// in both published dialects.
///
/// The assertions are on decoded JSON rather than on a produced string, because the point of the
/// encoding is structural: a `tools` key present when it should be absent is a claim that the model
/// was handed a capability, and a wrong role or a missing id is a result a server cannot match to the
/// call it came from. A raw-string comparison would catch neither.
final class ToolWireTests: XCTestCase {

    private let searchTool = ToolDefinition(
        name: BuiltInTool.webSearch,
        blurb: "Search the web with one query.",
        parameters: ToolParameterSchema(
            properties: ["query": ToolParameter(kind: .string, description: "The query.")],
            required: ["query"]
        ),
        networkClass: .publicInternet
    )

    private func wireJSON(_ body: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    private func messages(_ body: Data) throws -> [[String: Any]] {
        try XCTUnwrap(wireJSON(body)["messages"] as? [[String: Any]])
    }

    private func turn(
        _ protocolUsed: ToolCallingProtocol, _ tools: [ToolDefinition],
        extra: ChatMessagePayload? = nil
    ) -> GenerationRequest {
        var built = [ChatMessagePayload(role: .user, text: "What changed in Paris today?")]
        if let extra { built.append(extra) }
        return GenerationRequest(
            modelID: "qwen3:8b", messages: built, config: .default,
            tools: tools, toolProtocol: protocolUsed
        )
    }

    private func bodies(_ request: GenerationRequest) throws -> [(String, Data)] {
        [
            ("ollama", try OllamaCodec.chatRequestBody(request, support: .all)),
            ("openai", try OpenAICodec.chatRequestBody(request, support: .all)),
        ]
    }

    /// Both dialects publish the same schema shape, and the blurb is the only model-facing sentence a
    /// tool has. A dropped `description` is a tool the server accepts and then misuses.
    func testANativeTurnCarriesTheToolSchemaInBothDialects() throws {
        for (label, body) in try bodies(turn(.native, [searchTool])) {
            let tools = try XCTUnwrap(wireJSON(body)["tools"] as? [[String: Any]], "\(label) sends tools")
            XCTAssertEqual(tools.count, 1, label)
            let entry = try XCTUnwrap(tools.first, label)
            XCTAssertEqual(entry["type"] as? String, "function", label)
            let function = try XCTUnwrap(entry["function"] as? [String: Any], label)
            XCTAssertEqual(function["name"] as? String, BuiltInTool.webSearch, label)
            XCTAssertEqual(function["description"] as? String, "Search the web with one query.", label)
            let schema = try XCTUnwrap(function["parameters"] as? [String: Any], label)
            XCTAssertEqual(schema["type"] as? String, "object", label)
            XCTAssertEqual(schema["required"] as? [String], ["query"], label)
            let properties = try XCTUnwrap(schema["properties"] as? [String: Any], label)
            XCTAssertEqual((properties["query"] as? [String: Any])?["type"] as? String, "string", label)
        }
    }

    /// A prompt-protocol turn was told the call shapes in its system block; a tools-off turn was told
    /// nothing. Either one carrying a `tools` key advertises a capability the model was not given, and
    /// sending both is how a model emits one call twice.
    func testAPromptProtocolOrToolsOffTurnCarriesNoToolsAndNoToolVocabulary() throws {
        let cases: [(String, GenerationRequest)] = [
            ("ollama-prompt", turn(.prompt, [searchTool])),
            ("ollama-off", turn(.none, [])),
            ("openai-prompt", turn(.prompt, [searchTool])),
            ("openai-off", turn(.none, [])),
        ]
        for (label, request) in cases {
            let body = label.hasPrefix("ollama")
                ? try OllamaCodec.chatRequestBody(request, support: .all)
                : try OpenAICodec.chatRequestBody(request, support: .all)
            let json = try XCTUnwrap(String(data: body, encoding: .utf8))
            XCTAssertNil(try wireJSON(body)["tools"], "\(label) sends no tools key at all")
            XCTAssertFalse(json.contains("tools"), "\(label) names tools nowhere")
            XCTAssertFalse(json.contains(BuiltInTool.webSearch), "\(label) names a tool nowhere")
        }
    }

    /// A tool result answers one named call, so the dialect's tool role and the id it carries are the
    /// whole pairing. Cairn's stored role stays `.user`: a wire role for one message is not a fact
    /// about the conversation, and a new `ChatRole` case would put that wire detail in every node.
    func testAToolResultTravelsAsTheToolRoleWithTheCallItAnswers() throws {
        let result = ChatMessagePayload.toolResult(callID: "call-7", text: "3 results found.")
        for (label, body) in try bodies(turn(.native, [searchTool], extra: result)) {
            let sent = try messages(body)
            XCTAssertEqual(sent.count, 2, label)
            XCTAssertEqual(sent[0]["role"] as? String, "user", "\(label) keeps the user turn as it was")
            XCTAssertNil(sent[0]["tool_call_id"], "\(label) marks only the answering message")
            let answer = try XCTUnwrap(sent.last, label)
            XCTAssertEqual(answer["role"] as? String, "tool", label)
            XCTAssertEqual(answer["tool_call_id"] as? String, "call-7", label)
            XCTAssertEqual(answer["content"] as? String, "3 results found.", label)
        }
        XCTAssertEqual(
            ChatRole.allCases.map(\.rawValue), ["system", "user", "assistant"],
            "a wire role for one message never became a stored role"
        )
    }
}

