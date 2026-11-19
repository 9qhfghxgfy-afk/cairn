import Foundation

/// The system-prompt block that names this turn's tools.
///
/// One renderer for both formats, because the block the live preview shows has to be the block that
/// goes on the wire — the same rule `ContextAssembly` holds for every other injected block. The
/// difference between the two formats is only how much the model has to be told: a backend with a
/// real `tools` array is told the schemas by the request, so its block is a policy line and a name
/// list; a backend without one has to be shown the shapes, which is `PromptToolProtocol.instruction`.
///
/// An empty definition list renders the empty string. That is how "tools off" is guaranteed: not a
/// filter at the last moment, but a block that has nothing in it to send.
public enum ToolPromptBlock {

    /// The longest form, used for budget measurement: measuring the smaller block and then sending
    /// the larger one is how a prompt overflows the window.
    public static func render(
        _ definitions: [ToolDefinition],
        format: ToolCallingProtocol = .prompt
    ) -> String {
        guard !definitions.isEmpty else { return "" }
        switch format {
        case .prompt: return PromptToolProtocol.instruction(for: definitions)
        case .native: return nativeListing(definitions)
        case .none: return ""
        }
    }

    /// What a backend with native tool calling is told in the system block: the schemas are already
    /// in its request, so this only sets what to do with them.
    public static func nativeListing(_ definitions: [ToolDefinition]) -> String {
        let names = definitions.map(\.name).sorted()
        let base = """
            Tools are available on this request: \(names.joined(separator: ", ")). \
            Call one instead of guessing, and say which one you used. Only report a result a tool \
            actually returned — a call you did not make has told you nothing.
            """
        // The same line the prompt format gets: a native backend is told the schemas by its request, but
        // not what to do with a refusal, and a refused location read is the one answer a model is most
        // tempted to fill in itself.
        let guidance = ToolPromptBlock.guidance(for: definitions)
        return guidance.isEmpty ? base : base + "\n" + guidance
    }

    /// The names offered, for `TurnContext` and for the transcript's record of what a turn could do.
    public static func names(_ definitions: [ToolDefinition]) -> [String] {
        definitions.map(\.name).sorted()
    }

    /// The extra line a tool needs beyond its own blurb, for the set offered on this turn.
    ///
    /// Only `get_location` has one. Its blurb already says the tool can be refused, and a model that
    /// reads a refusal and then names a city anyway has invented precisely the thing this tool exists to
    /// keep honest — so the rule is stated once more, in the block rather than in a tool result a model
    /// may skim past. An offer with no location tool in it renders the empty string, so nothing is added
    /// to a prompt that cannot use it.
    public static func guidance(for definitions: [ToolDefinition]) -> String {
        guard definitions.contains(where: { $0.name == BuiltInTool.getLocation }) else { return "" }
        return """
            get_location answers only after the user allows it. If it reports that it was refused, \
            that Location Services are off, or that the device did not answer, that is the whole of \
            what you know about where they are: say so, and do not name a place, a city or a time zone.
            """
    }
}
