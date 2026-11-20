import Foundation

/// Fits one turn's prompt to an engine that states how much context it holds.
///
/// An on-device model fails the whole turn when the prompt is one turn of history too long, and the
/// failure arrives as a framework error that says nothing a person can act on. So the fit is done
/// here, before the request goes out: drop the oldest turns, then the tool block, and if even the
/// last question alone does not fit, say so as its own reason rather than let the engine throw.
///
/// Counted in characters, deliberately. There is no tokenizer in this module, and a token count
/// invented from character counts would be presented as a measurement. Four characters to a token is
/// the rate this app documents and applies consistently; it is an estimate, and the reserve below is
/// what keeps an estimate from being optimistic at exactly the wrong moment.
public enum PromptContextFit {
    /// The documented estimate: four characters to a token for the scripts Cairn is used with.
    public static let charactersPerToken = 4
    /// Tokens held back for the answer. A prompt that fills the window leaves room for no reply, so
    /// fitting to the window exactly is not the target.
    public static let responseReserveTokens = 512

    /// The character ceiling for instructions plus history, given an engine's token ceiling.
    /// Never negative: a ceiling at or below the reserve means nothing fits, which is reported as
    /// "does not fit" rather than as an empty prompt.
    public static func characterCeiling(tokenCeiling: Int) -> Int {
        max(0, (tokenCeiling - responseReserveTokens) * charactersPerToken)
    }

    /// What a turn was shortened to, and what that cost.
    public struct Fitted: Sendable, Equatable {
        public var instructions: String
        public var body: String
        /// Turns of history removed, oldest first.
        public var droppedTurnCount: Int
        /// True when the tool block had to come out — the model was told nothing about tools, so a
        /// caller must not describe the answer as a tool turn.
        public var droppedToolBlock: Bool
        /// False when even the newest turn alone is over the ceiling. The caller then refuses the
        /// turn with a reason instead of sending something the engine will reject.
        public var fits: Bool

        public var characterCount: Int { instructions.count + body.count }
    }

    /// Fits a turn. `toolBlock` is the exact block the caller appended to the system text, so
    /// removing it is a subtraction and not a guess about how the block was worded.
    public static func fit(
        systemText: String?,
        body: String,
        toolBlock: String = "",
        tokenCeiling: Int
    ) -> Fitted {
        let ceiling = characterCeiling(tokenCeiling: tokenCeiling)
        var instructions = systemText ?? ""
        var turns = body.components(separatedBy: "\n\n")
        var dropped = 0
        var droppedTools = false

        func total() -> Int { instructions.count + turns.joined(separator: "\n\n").count }

        // Oldest history first: the question just asked is the one that must be answered, and an
        // earlier exchange is the part the reader has already seen.
        while total() > ceiling, turns.count > 1 {
            turns.removeFirst()
            dropped += 1
        }
        // The tool block next. Losing it costs the turn its tools, which is honest and visible;
        // losing the question costs the turn its answer.
        if total() > ceiling, !toolBlock.isEmpty, toolBlock.count < instructions.count {
            let stripped = strip(instructions, toolBlock: toolBlock)
            if stripped.count < instructions.count {
                instructions = stripped
                droppedTools = true
            }
        }
        let joined = turns.joined(separator: "\n\n")
        let fits = instructions.count + joined.count <= ceiling
        return Fitted(
            instructions: instructions,
            body: joined,
            droppedTurnCount: dropped,
            droppedToolBlock: droppedTools,
            fits: fits
        )
    }

    /// Removes the tool block from the end of the system text and tidies the seam it left.
    private static func strip(_ instructions: String, toolBlock: String) -> String {
        guard instructions.hasSuffix(toolBlock) else { return instructions }
        let head = String(instructions.dropLast(toolBlock.count))
        let trimmed = head.reversed().drop(while: { $0.isWhitespace }).reversed()
        return String(trimmed)
    }
}
