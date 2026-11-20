import Foundation

/// Reading one attribute-form tag out of model text.
///
/// The scanning half of `PromptAttributeCall`, kept apart from the typing half so each file stays
/// small and does one thing: this file walks characters and decides whether a `<` starts a tag that
/// names an offered tool; `PromptAttributeCall.swift` decides what the tag's arguments mean. The two
/// meet at `read(_:)`, which is module-internal rather than private for exactly that reason.
extension PromptAttributeCall {
    /// Reads one tag starting at `open`, or nil when what begins there is not an offered tool's call.
    static func read(
        _ text: Substring, open: String.Index, schemas: [String: ToolParameterSchema]
    ) -> PromptAttributeCall? {
        var cursor = text.index(after: open)
        var name = ""
        while cursor < text.endIndex, isNameCharacter(text[cursor]) {
            name.append(text[cursor])
            cursor = text.index(after: cursor)
        }
        guard !name.isEmpty, ToolCall.isLegalName(name), let schema = schemas[name] else { return nil }

        var attributes: [(key: String, value: String)] = []
        var isSelfClosed = false
        var headerClosed = false
        while cursor < text.endIndex {
            skipWhitespace(in: text, to: &cursor)
            guard cursor < text.endIndex else { break }
            let character = text[cursor]
            if character == "/" {
                let next = text.index(after: cursor)
                guard next < text.endIndex, text[next] == ">" else { return nil }
                isSelfClosed = true
                cursor = text.index(after: next)
                headerClosed = true
                break
            }
            if character == ">" {
                cursor = text.index(after: cursor)
                headerClosed = true
                break
            }
            guard let attribute = readAttribute(in: text, at: &cursor) else { return nil }
            attributes.append(attribute)
        }
        // A header that never closed is a half-written tag — the model is still generating, or this was
        // never markup. Nothing is acted on until at least the `>` arrives.
        guard headerClosed else { return nil }

        let headerEnd = cursor
        var end = headerEnd
        var body = ""
        if !isSelfClosed {
            // A closing half is what a body needs, but a header that closed with `>` and never finds
            // `</name>` is a tag the model wrote argument-only — models leave the `/` out as often as they
            // put it in. Its arguments stand; only a *body* needs the closing half.
            body = ""
            end = headerEnd
            if let close = closingTag(named: name, in: text, from: headerEnd) {
                body = String(text[headerEnd..<close.lowerBound])
                end = close.upperBound
            }
        }
        let arguments = arguments(from: attributes, body: body, schema: schema)
        return PromptAttributeCall(
            range: open..<end,
            name: name,
            arguments: arguments,
            isCallable: !arguments.isEmpty || schema.required.isEmpty
        )
    }

    private static func readAttribute(
        in text: Substring, at cursor: inout String.Index
    ) -> (key: String, value: String)? {
        let nameStart = cursor
        while cursor < text.endIndex, isNameCharacter(text[cursor]) {
            cursor = text.index(after: cursor)
        }
        let key = String(text[nameStart..<cursor])
        guard !key.isEmpty, ToolCall.isLegalName(key) else { return nil }

        skipWhitespace(in: text, to: &cursor)
        guard cursor < text.endIndex, text[cursor] == "=" else { return (key, "") }
        cursor = text.index(after: cursor)
        skipWhitespace(in: text, to: &cursor)
        guard cursor < text.endIndex else { return nil }

        let character = text[cursor]
        if character == "\"" || character == "'" {
            let quote = character
            let valueStart = text.index(after: cursor)
            var scan = valueStart
            while scan < text.endIndex, text[scan] != quote { scan = text.index(after: scan) }
            // The closing quote has not arrived: the value is still being generated, so this tag is not
            // a call yet.
            guard scan < text.endIndex else { return nil }
            cursor = text.index(after: scan)
            return (key, String(text[valueStart..<scan]))
        }
        // An unquoted value is accepted because models write `query=Paris`. It ends at whitespace, `/`
        // or `>`, which is where a value written that way has to end anyway.
        let valueStart = cursor
        while cursor < text.endIndex, !isValueBoundary(text[cursor]) {
            cursor = text.index(after: cursor)
        }
        return (key, String(text[valueStart..<cursor]))
    }

    /// The matching `</name>`, found by walking the `<` characters rather than by a string search, so a
    /// scan window of an answer keeps its indices against the whole text.
    private static func closingTag(
        named name: String, in text: Substring, from start: String.Index
    ) -> Range<String.Index>? {
        let needle = "</\(name)>"
        var cursor = start
        while let hit = text[cursor...].firstIndex(of: "<") {
            let tail = text[hit...]
            if tail.hasPrefix(needle) {
                return hit..<tail.index(tail.startIndex, offsetBy: needle.count)
            }
            let next = text.index(after: hit)
            if next >= text.endIndex { break }
            cursor = next
        }
        return nil
    }

    private static func skipWhitespace(in text: Substring, to cursor: inout String.Index) {
        while cursor < text.endIndex, text[cursor].isWhitespace {
            cursor = text.index(after: cursor)
        }
    }

    private static func isNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
            || character == "-" || character == "."
    }

    private static func isValueBoundary(_ character: Character) -> Bool {
        character.isWhitespace || character == ">" || character == "/"
    }
}
