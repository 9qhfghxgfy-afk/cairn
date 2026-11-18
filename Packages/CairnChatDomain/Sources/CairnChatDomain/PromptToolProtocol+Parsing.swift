import Foundation

// Finding call blocks in a model's answer, and knowing exactly where they were so they can be
// lifted back out of it.
//
// No regular expressions, and every loop bounded by `callLimit` plus the scan and body windows. The
// reason is not taste: a model's output is untrusted input, and an unbounded pattern over it is how
// one bad reply stops the app instead of returning one bad tool call.
extension PromptToolProtocol {

    /// `<function=name><parameter=key>value</parameter></function>` — the shape local chat templates
    /// publish, and the same shape the on-device template codec reads.
    static func tagCalls(in text: String) -> [Located] {
        var out: [Located] = []
        var cursor = text.startIndex
        while out.count < callLimit,
              let open = text.range(of: "<function=", range: cursor..<text.endIndex) {
            guard let nameEnd = text[open.upperBound...].firstIndex(of: ">") else {
                cursor = open.upperBound
                continue
            }
            let name = text[open.upperBound..<nameEnd]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let close = text.range(of: "</function>", range: nameEnd..<text.endIndex)
            // An unterminated block is read only as far as the body bound, never to the end of the
            // reply: a model that never closes its tag must not turn all its prose into arguments.
            let end = close?.upperBound ?? text[nameEnd...].prefix(bodyCharacterLimit).endIndex
            if nameEnd < end, ToolCall.isLegalName(name) {
                var arguments = parameterPairs(in: text[nameEnd..<end])
                arguments.removeValue(forKey: "name")
                let json = JSONValue.dictionary(arguments.mapValues { JSONValue.text($0) }).encoded
                out.append(Located(
                    start: open.lowerBound,
                    end: end,
                    request: ToolCallRequest(
                        id: "prompt-\(name)-\(out.count + 1)",
                        name: name,
                        argumentsJSON: String(data: json ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
                    )
                ))
            }
            cursor = end > open.upperBound ? end : open.upperBound
        }
        return out
    }

    /// `{"name": "…", "arguments": {…}}` — the JSON shape, which is also accepted as `function` /
    /// `parameters`, because both spellings appear in published templates.
    static func jsonCalls(in text: String) -> [Located] {
        var out: [Located] = []
        var cursor = text.startIndex
        while out.count < callLimit,
              let brace = text.range(of: "{", range: cursor..<text.endIndex) {
            let window = text[brace.lowerBound...].prefix(bodyCharacterLimit)
            guard let object = balancedObject(in: window) else {
                cursor = brace.upperBound
                continue
            }
            guard let request = request(
                fromJSONObject: object.object, callID: "prompt-json-\(out.count + 1)"
            ) else {
                cursor = brace.upperBound
                continue
            }
            out.append(Located(start: brace.lowerBound, end: object.end, request: request))
            cursor = object.end
        }
        return out
    }
}
