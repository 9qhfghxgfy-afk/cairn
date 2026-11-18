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
        return """
            Tools are available on this request: \(names.joined(separator: ", ")). \
            Call one instead of guessing, and say which one you used. Only report a result a tool \
            actually returned — a call you did not make has told you nothing.
            """
    }

    /// The names offered, for `TurnContext` and for the transcript's record of what a turn could do.
    public static func names(_ definitions: [ToolDefinition]) -> [String] {
        definitions.map(\.name).sorted()
    }
}
