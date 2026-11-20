import Foundation

/// The prompt protocol read against the tools this turn actually offered.
///
/// `parse(_:)` alone has to guess whether `<b>` is a tool, so it only reads the two shapes it
/// publishes. Given the offered definitions it can also read the attribute form that instruct models
/// really write — `<web_search query="Paris" />` — and it can tell a call from HTML, because a name
/// that was not offered is not a call. This is the entry point a live turn uses; `parse(_:)` stays for
/// wire tests and for callers with no tool list to check against.
///
/// `ToolCallCodec` in `CairnInferenceNative` reads the same shape for the device-template transport.
/// The two stay in step by test, not by import: `CairnInferenceLocal` and the Swift 5 island may not
/// depend on each other, so the shape is published here and mirrored there.
extension PromptToolProtocol {
    /// Attribute-form calls in `text`, restricted to the offered names, arguments typed by each tool's
    /// own schema. Same call and scan bounds as every other read here.
    public static func attributeCalls(_ text: String, offered: [ToolDefinition]) -> [ToolCallRequest] {
        guard !offered.isEmpty else { return [] }
        let window = text.prefix(scanCharacterLimit)
        return PromptAttributeCall.scan(window, offered: offered, limit: callLimit)
            .filter(\.isCallable)
            .enumerated()
            .map { position, found in
                ToolCallRequest(
                    id: "prompt-attr-\(position + 1)",
                    name: found.name,
                    argumentsJSON: encodedArguments(found.arguments)
                )
            }
    }

    /// Both published shapes plus the attribute form: everything this turn's tools could be called with.
    /// Published shapes first, then attribute tags, each group in the order it was written.
    public static func parse(_ text: String, offered: [ToolDefinition]) -> [ToolCallRequest] {
        parse(text) + attributeCalls(text, offered: offered)
    }

    /// Answer text with every tool tag struck out, including a malformed one.
    ///
    /// A tag naming an offered tool never survives into what the user reads, even when its arguments
    /// were too broken to execute: the alternative is showing `<web_search>` markup as an answer. The
    /// two published shapes are then struck by `strippedText(_:)` as usual.
    public static func strippedText(_ text: String, offered: [ToolDefinition]) -> String {
        guard !offered.isEmpty else { return strippedText(text) }
        let window = text.prefix(scanCharacterLimit)
        let spans = PromptAttributeCall.scan(window, offered: offered, limit: callLimit).map(\.range)
        guard !spans.isEmpty else { return strippedText(text) }
        return trimmed(strippedText(removing(text, spans: wholeLines(in: text, spans: spans))))
    }

    /// A tag alone on its line takes the line with it; one in the middle of a sentence does not take the
    /// sentence. Without this, a struck call on its own line leaves the blank line where it sat.
    private static func wholeLines(in text: String, spans: [Range<String.Index>]) -> [Range<String.Index>] {
        spans.map { span in
            let start = Self.lineStart(of: text, at: span.lowerBound)
            let lineEnd = text[span.upperBound...].firstIndex(of: "\n") ?? text.endIndex
            let before = text[start..<span.lowerBound]
            let after = text[span.upperBound..<lineEnd]
            guard before.allSatisfy(\.isWhitespace), after.allSatisfy(\.isWhitespace) else { return span }
            // Swallow the line break too, so the two prose lines around the tag close up.
            let beyond = lineEnd < text.endIndex ? text.index(after: lineEnd) : lineEnd
            return start..<beyond
        }
    }

    private static func lineStart(of text: String, at index: String.Index) -> String.Index {
        var cursor = index
        while cursor > text.startIndex {
            let previous = text.index(before: cursor)
            if text[previous] == "\n" { return cursor }
            cursor = previous
        }
        return text.startIndex
    }

    /// Drops the given spans in one pass. Overlapping spans are skipped rather than cut twice — a JSON
    /// block written inside a tag body sits inside that tag's own span.
    private static func removing(_ text: String, spans: [Range<String.Index>]) -> String {
        var kept = ""
        var cursor = text.startIndex
        for span in spans.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if span.lowerBound < cursor { continue }
            kept += text[cursor..<span.lowerBound]
            cursor = span.upperBound
        }
        kept += text[cursor...]
        return kept
    }

    /// What a struck tag leaves behind: the space it was separated from, and any leading or trailing
    /// break. Paragraphing that the model wrote itself is left alone.
    private static func trimmed(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n").map { line in
            var end = line.endIndex
            while end > line.startIndex, line[line.index(before: end)].isWhitespace {
                end = line.index(before: end)
            }
            return String(line[..<end])
        }
        return lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Arguments as the wire JSON the executor already parses. Sorted keys, so two identical turns send
    /// identical bytes and a wire test can assert on the call rather than on dictionary order.
    private static func encodedArguments(_ arguments: [String: JSONValue]) -> String {
        guard !arguments.isEmpty else { return "{}" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(arguments),
              let json = String(data: data, encoding: .utf8)
        else { return "{}" }
        return json
    }
}
