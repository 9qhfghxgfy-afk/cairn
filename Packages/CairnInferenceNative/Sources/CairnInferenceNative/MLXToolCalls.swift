import CairnChatDomain
import Foundation

#if !targetEnvironment(simulator) && canImport(MLXLMCommon)
import MLXLMCommon

/// One tool call the runtime parsed, turned into Cairn's request.
///
/// Both packages call this type `ToolCall`, so both are spelled out with their module here — the clash is
/// the fact worth leaving visible rather than papering over with a typealias.
///
/// The arguments stay raw JSON text, exactly as the runtime emitted them. Cairn parses them only after
/// the user approves the call, which is the same rule the remote dialects follow.
enum MLXToolCalls {
    static func request(_ call: MLXLMCommon.ToolCall, id: String) -> ToolCallRequest? {
        let name = call.function.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard CairnChatDomain.ToolCall.isLegalName(name) else { return nil }
        return ToolCallRequest(
            id: id, name: name, argumentsJSON: argumentsJSON(call.function.arguments)
        )
    }

    /// Written back out through the runtime's own conversion (`anyValue`, then JSON), because a value
    /// Cairn re-typed on the way through would be a value the tool did not receive.
    private static func argumentsJSON(_ arguments: [String: MLXLMCommon.JSONValue]) -> String {
        guard !arguments.isEmpty else { return "{}" }
        let plain = arguments.mapValues { $0.anyValue }
        guard JSONSerialization.isValidJSONObject(plain),
              let data = try? JSONSerialization.data(withJSONObject: plain),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }
}
#endif
