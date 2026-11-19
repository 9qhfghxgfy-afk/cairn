import Foundation

/// The documented prompt protocol for a backend that has no native function calling.
///
/// Plenty of useful models cannot emit structured tool calls, and refusing to give them tools at all
/// would make the `Tools` chip depend on which model happens to be loaded. So there is a second,
/// published path: Cairn writes an instruction block naming the tools, the model writes a call block
/// in its answer, and Cairn reads it back under a hard bound.
///
/// The two shapes read here are the ones already published by local chat templates — a JSON object,
/// and `<function=name><parameter=key>value</parameter></function>` — not an invention, so a model
/// primed by its own template is understood rather than corrected. Parsing is strict and bounded: a
/// fixed number of calls, a fixed scan window, a fixed argument size, and no regex. Anything that
/// does not parse is left as the text it was, which is the honest outcome for a model that wrote
/// prose.
public enum PromptToolProtocol {
    /// Calls read out of one answer. Beyond this the loop would be spending steps on a model that is
    /// not calling tools, it is hallucinating call-shaped text.
    public static let callLimit = 4
    /// How much of an answer is scanned for call blocks.
    public static let scanCharacterLimit = 12_000
    /// One call body's size, and one argument's size, both.
    public static let bodyCharacterLimit = 4_096

    /// The instruction block. Emitted only when tools are live on the turn **and** the backend has
    /// no native tool calling — a model that has a real `tools` array does not need to be told to
    /// write tags, and telling it to would produce both at once.
    public static func instruction(for definitions: [ToolDefinition]) -> String {
        guard !definitions.isEmpty else { return "" }
        var lines: [String] = [
            "You may call tools on this reply by writing a call block instead of an answer.",
            "Write at most \(callLimit) call blocks, each on its own line:",
            "",
            "  <function=TOOL_NAME><parameter=ARGUMENT_NAME>VALUE</parameter></function>",
            "",
            "or the equivalent JSON form, one object per line:",
            "",
            "  {\"name\": \"TOOL_NAME\", \"arguments\": {\"ARGUMENT_NAME\": \"VALUE\"}}",
            "",
            "If you write a call block, write nothing else in that reply — the block is the whole",
            "reply. The tool's result comes back on the next turn, so do not invent what it said.",
            "If you already know the answer, answer; a tool you did not call has told you nothing.",
            "",
            "Tools on this reply:",
        ]
        for definition in definitions {
            let names = definition.parameters.properties.keys.sorted()
            let arguments = names.isEmpty
                ? "takes no arguments"
                : "arguments: \(names.joined(separator: ", "))"
            let blurb = definition.blurb
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("- \(definition.name) — \(arguments). \(blurb)")
        }
        // A tool whose refusal is a real answer gets one more line, in the block the model reads rather
        // than in a result it might not. `ToolPromptBlock` owns which tools need it.
        let guidance = ToolPromptBlock.guidance(for: definitions)
        if !guidance.isEmpty {
            lines.append("")
            lines.append(guidance)
        }
        return lines.joined(separator: "\n")
    }

    /// Call blocks found in one answer, in the order they appear, capped at `callLimit`.
    public static func parse(_ text: String) -> [ToolCallRequest] {
        let window = String(text.prefix(scanCharacterLimit))
        let located = tagCalls(in: window) + jsonCalls(in: window)
        return located
            .sorted { $0.start < $1.start }
            .prefix(callLimit)
            .map(\.request)
    }

    /// The answer with its call blocks removed, so the transcript shows what the model meant rather
    /// than a wall of markup. Text with no call block in it comes back untouched.
    public static func strippedText(_ text: String) -> String {
        let window = String(text.prefix(scanCharacterLimit))
        let located = (tagCalls(in: window) + jsonCalls(in: window))
            .sorted { $0.start < $1.start }
            .prefix(callLimit)
        guard !located.isEmpty else { return text }
        var kept = window
        for found in located.sorted(by: { $0.start > $1.start }) {
            kept.removeSubrange(found.start..<found.end)
        }
        return Self.collapseBlankLines(kept)
    }

    public static func containsCall(_ text: String) -> Bool {
        !parse(text).isEmpty
    }

    /// A call block is markup, not prose, so removing it may leave a run of blank lines behind.
    static func collapseBlankLines(_ text: String) -> String {
        var out = text
        while out.contains("\n\n\n") { out = out.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One located call, with the exact range it occupied so it can be removed from the answer.
    ///
    /// Ordering is by `String.Index`, which is only meaningful because every `Located` in a batch is
    /// found by scanning the *same* string — the two scanners in `Parsing` share one scan window.
    struct Located {
        var start: String.Index
        var end: String.Index
        var request: ToolCallRequest
    }
}
