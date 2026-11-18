import Foundation

// Reading one call block once it has been located: its parameters, and where it ends.
extension PromptToolProtocol {

    /// `<parameter=key>value</parameter>` pairs inside one call region, each value size-bounded.
    static func parameterPairs(in region: Substring) -> [String: String] {
        var found: [String: String] = [:]
        var search = region
        while found.count < callLimit * 4, let open = search.range(of: "<parameter=") {
            let after = search[open.upperBound...]
            guard let keyEnd = after.firstIndex(of: ">") else { break }
            let key = after[after.startIndex..<keyEnd]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let body = after[after.index(after: keyEnd)...]
            guard let close = body.range(of: "</parameter>") else { break }
            if ToolCall.isLegalName(key) {
                let value = body[body.startIndex..<close.lowerBound].prefix(bodyCharacterLimit)
                found[key] = String(value)
            }
            search = search[close.upperBound...]
        }
        return found
    }

    /// The first balanced `{…}` at the start of a slice, plus the index just past it. Braces inside
    /// string values are not tracked: an object that misparses as a result fails to decode, which is
    /// a declined call rather than a wrong one.
    static func balancedObject(in slice: Substring) -> (object: Substring, end: String.Index)? {
        var depth = 0
        var index = slice.startIndex
        while index < slice.endIndex {
            let character = slice[index]
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 {
                    return (slice[slice.startIndex...index], slice.index(after: index))
                }
            }
            index = slice.index(after: index)
        }
        return nil
    }

    static func request(fromJSONObject object: Substring, callID: String) -> ToolCallRequest? {
        guard let decoded = JSONValue.decode(from: Data(object.utf8)),
              let fields = decoded.dictionaryValue,
              let name = fields["name"]?.coercedText
                ?? fields["function"]?.dictionaryValue?["name"]?.coercedText,
              ToolCall.isLegalName(name)
        else { return nil }
        return ToolCallRequest(
            id: callID,
            name: name,
            argumentsJSON: argumentsJSON(fields["arguments"] ?? fields["parameters"])
        )
    }

    /// Arguments stay a JSON string until a registry parses them — which is how a malformed blob
    /// becomes one declined call instead of a crash, and it is also what a native backend sends.
    static func argumentsJSON(_ value: JSONValue?) -> String {
        switch value {
        case .dictionary:
            guard let data = value?.encoded,
                  let text = String(data: data, encoding: .utf8)
            else { return "{}" }
            return text
        case .text(let raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasPrefix("{") ? trimmed : "{}"
        default:
            return "{}"
        }
    }
}
