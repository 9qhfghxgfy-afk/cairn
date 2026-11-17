import Foundation

/// Builds the exact system block Cairn injects for a turn.
///
/// This is the single source of that text: the live preview in the configuration sheet and the
/// string that goes on the wire are produced by the same call, so a preview that says one thing and
/// a request that says another is not possible by construction. Two rules hold it honest:
///
/// - **Order is fixed.** Persona first, then the always-injected group in `alwaysOnKeys` order,
///   then the conditional group in `conditionalKeys` order. Same inputs, byte-identical output.
/// - **A conditional block needs its feature.** A toggle that is on describes nothing on a turn
///   where the feature is not running, so nothing is written.
public enum ContextAssembly {
    public static func blocks(
        persona: String,
        toggles: ContextToggleSet,
        format: ResponseFormatPreference,
        environment: ContextEnvironment,
        turn: TurnContext
    ) -> [String] {
        var out: [String] = []
        let personaText = persona.trimmingCharacters(in: .whitespacesAndNewlines)
        if !personaText.isEmpty { out.append(personaText) }

        for key in ContextToggleSet.alwaysOnKeys {
            guard toggles.value(key) else { continue }
            if let block = alwaysBlock(
                for: key, environment: environment, turn: turn, format: format
            ) {
                out.append(block)
            }
        }

        for key in ContextToggleSet.conditionalKeys {
            guard toggles.value(key), isLive(key, turn: turn) else { continue }
            if let block = conditionalBlock(for: key, turn: turn) { out.append(block) }
        }
        return out
    }

    public static func assemble(
        persona: String,
        toggles: ContextToggleSet,
        format: ResponseFormatPreference,
        environment: ContextEnvironment,
        turn: TurnContext
    ) -> String {
        blocks(
            persona: persona, toggles: toggles, format: format,
            environment: environment, turn: turn
        ).joined(separator: "\n\n")
    }

    /// Whether the feature a conditional block describes is really running this turn.
    public static func isLive(_ key: ContextKey, turn: TurnContext) -> Bool {
        switch key {
        case .toolGuidance: return turn.toolsActive
        case .forceWebFetch: return turn.webFetchActive
        case .fileContext: return turn.fileCount > 0
        case .imageContext: return turn.imageCount > 0
        default: return true
        }
    }
}
