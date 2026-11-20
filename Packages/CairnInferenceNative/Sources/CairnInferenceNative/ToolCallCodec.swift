import CairnChatDomain
import Foundation

/// Reads a tool region into a `ToolCallRequest`.
///
/// Local templates differ: some emit a JSON object, some emit nested function/parameter tags.
/// Both are read here because they are both published formats, and nothing is invented — a body
/// that yields no tool name returns nil, and the caller decides whether to show it as text.
/// The arguments stay raw JSON exactly as emitted; Cairn parses them only after the user
/// approves the call.
public enum ToolCallCodec {
    public static func decode(_ body: String, callID: String = "device-call") -> ToolCallRequest? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("{"), let json = fromJSON(trimmed) { return json }
        return fromTagForm(trimmed, callID: callID)
    }

    /// Reads a tool region against the tools the turn actually offered.
    ///
    /// The two shapes above need no tool list because they name the tool inside their own markup. A local
    /// model also writes the flatter attribute form — `<get_weather city="Paris" />` — which is only safe
    /// to read when the offered names gate it, so this overload asks for them. Typing comes from the
    /// domain's own reader (`PromptToolProtocol.attributeCalls`), which both sides of the module boundary
    /// may see: this island may not reach into the inference-local module, and the domain is the one
    /// place the shape can be published once. `ToolCallCodecTests` is what keeps the two readers in step.
    public static func decode(
        _ body: String, offered: [ToolDefinition], callID: String = "device-call"
    ) -> ToolCallRequest? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("{"), let json = fromJSON(trimmed) { return json }
        if let tagged = fromTagForm(trimmed, callID: callID) { return tagged }
        guard let call = PromptToolProtocol.attributeCalls(trimmed, offered: offered).first else {
            return nil
        }
        return ToolCallRequest(id: callID, name: call.name, argumentsJSON: call.argumentsJSON)
    }


    /// `{"name": "search", "arguments": {"query": "…"}}`, tolerating `function` /
    /// `parameters` and an arguments value already encoded as a string.
    static func fromJSON(_ text: String) -> ToolCallRequest? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let name = (object["name"] as? String)
            ?? (object["function"] as? [String: Any])?["name"] as? String
        guard let name, !name.isEmpty else { return nil }

        let arguments = object["arguments"] ?? object["parameters"]
        return ToolCallRequest(id: name, name: name, argumentsJSON: argumentsJSON(arguments))
    }

    static func argumentsJSON(_ value: Any?) -> String {
        if let text = value as? String, text.trimmingCharacters(in: .whitespaces).hasPrefix("{") {
            return text
        }
        let payload: Any = value is [String: Any] ? value : [:]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    /// `<function=name><parameter=query>…</parameter></function>`, the other published shape.
    static func fromTagForm(_ text: String, callID: String) -> ToolCallRequest? {
        let pairs = parameterPairs(in: text)
        let name = functionName(in: text) ?? pairs["name"]
        guard let name, !name.isEmpty else { return nil }
        var arguments = pairs
        arguments.removeValue(forKey: "name")
        guard let data = try? JSONSerialization.data(withJSONObject: arguments),
              let json = String(data: data, encoding: .utf8)
        else { return nil }
        return ToolCallRequest(id: callID, name: name, argumentsJSON: json)
    }

    static func functionName(in text: String) -> String? {
        guard let open = text.range(of: "<function=") else { return nil }
        let rest = text[open.upperBound...]
        let end = rest.firstIndex(of: ">") ?? rest.endIndex
        let name = rest[..<end].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    static func parameterPairs(in text: String) -> [String: String] {
        var found: [String: String] = [:]
        var search = Substring(text)
        while let open = search.range(of: "<parameter=") {
            let after = search[open.upperBound...]
            guard let nameEnd = after.firstIndex(of: ">") else { break }
            let key = after[..<nameEnd].trimmingCharacters(in: .whitespaces)
            let body = after[nameEnd...]
            guard let close = body.range(of: "</parameter>") else { break }
            found[key] = String(body[body.index(after: body.startIndex)..<close.lowerBound])
            search = search[close.upperBound...]
        }
        return found
    }
}
