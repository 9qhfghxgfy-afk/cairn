import Foundation

/// One attribute-form tag read out of model text: `<web_search query="Paris" />`.
///
/// The prompt protocol published two shapes for years — a JSON object and nested function/parameter
/// tags — and a model that answered with neither had its markup shown to the user as answer text.
/// Instruct models write the attribute form because that is what most of their training data looks
/// like, so Cairn reads it too. It is read **only** against the tools actually offered on the turn: a
/// `<b>` in prose or an `<a href="…">` in a pasted link is never a call, because `b` and `a` were not
/// offered. That restriction is what makes a lenient reader safe rather than a way for markup to leak.
///
/// No regex and no unbounded backscan, like every other read here: one forward pass over a bounded
/// window, and a tag whose closing half has not been generated yet is left for the next snapshot
/// rather than guessed at.
struct PromptAttributeCall {
    /// The span the tag occupies, so a caller can strike it out of visible text. `Substring.Index` is
    /// `String.Index`, so a range read out of a scan window is still usable against the whole answer.
    var range: Range<String.Index>
    var name: String
    var arguments: [String: JSONValue]
    /// False when the tag names an offered tool but carries nothing Cairn can act on — `<calculator />`
    /// with no expression. The markup is still struck out of the answer, because leaking it into prose
    /// is the failure this type exists to prevent, but no call is made from it.
    var isCallable: Bool

    /// Every attribute-form tag naming an offered tool, in the order written, capped at `limit`.
    static func scan(
        _ text: Substring, offered: [ToolDefinition], limit: Int
    ) -> [PromptAttributeCall] {
        guard !offered.isEmpty, limit > 0 else { return [] }
        var schemas: [String: ToolParameterSchema] = [:]
        for definition in offered { schemas[definition.name] = definition.parameters }

        var found: [PromptAttributeCall] = []
        var cursor = text.startIndex
        while let open = text[cursor...].firstIndex(of: "<") {
            guard let call = read(text, open: open, schemas: schemas) else {
                // Not a call. Step one character past this `<` so a page of prose is read once and a
                // stray `<` cannot make the scan quadratic.
                let next = text.index(after: open)
                if next >= text.endIndex { break }
                cursor = next
                continue
            }
            found.append(call)
            cursor = call.range.upperBound
            if found.count >= limit { break }
        }
        return found
    }

    /// The arguments a tag carries, typed against the tool's own schema.
    ///
    /// Attributes win outright. A bare body — `<web_search>Paris</web_search>` — is read as the tool's
    /// single required value, because that is the one thing the tool cannot do without; a tool with two
    /// required values, or one that takes nothing, gets no guess.
    static func arguments(
        from attributes: [(key: String, value: String)],
        body: String,
        schema: ToolParameterSchema
    ) -> [String: JSONValue] {
        var arguments: [String: JSONValue] = [:]
        for attribute in attributes {
            arguments[attribute.key] = value(attribute.value, as: schema.properties[attribute.key])
        }
        guard arguments.isEmpty else { return arguments }

        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, schema.required.count == 1 else { return [:] }
        let name = schema.required[0]
        return [name: value(trimmed, as: schema.properties[name])]
    }

    /// An attribute value is text, so a declared number, bool or list is parsed out of it. A value that
    /// will not parse stays a string and the tool answers with its own typed failure, which is a result
    /// the model can correct itself against — silently dropping the argument is not.
    private static func value(_ raw: String, as parameter: ToolParameter?) -> JSONValue {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parameter else { return .text(text) }
        switch parameter.kind {
        case .integer:
            if let number = Int(text) { return .integer(number) }
        case .number:
            if let number = Double(text) { return .number(number) }
        case .boolean:
            switch text.lowercased() {
            case "true", "yes", "1": return .boolean(true)
            case "false", "no", "0": return .boolean(false)
            default: break
            }
        case .stringArray:
            let parts = text.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return .array(parts.map { JSONValue.text($0) })
        case .string:
            break
        }
        return .text(text)
    }

}


