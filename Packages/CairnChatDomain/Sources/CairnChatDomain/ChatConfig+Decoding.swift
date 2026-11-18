import Foundation

/// A configuration blob written by an older build still has to decode.
///
/// Every key is read with `decodeIfPresent`. That is not defensive padding — it is what keeps P3's
/// added `toolToggle` (and every future knob) from turning an existing conversation's stored config
/// into an unreadable blob, which would drop the user's persona and their sampling settings on the
/// floor and fall back to a bare default. A missing key means "this chat predates the knob", and the
/// answer to that is the value a new chat would have had, not a decode error.
extension ChatConfig {
    private enum Keys: String, CodingKey {
        case persona, sampling, context, responseFormat, thinkingEnabled, toolToggle, hybrid
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: Keys.self)
        persona = try box.decodeIfPresent(String.self, forKey: .persona) ?? ""
        sampling = try box.decodeIfPresent(SamplingConfig.self, forKey: .sampling) ?? .unset
        context = try box.decodeIfPresent(ContextToggleSet.self, forKey: .context) ?? .default
        responseFormat = try box.decodeIfPresent(
            ResponseFormatPreference.self, forKey: .responseFormat
        ) ?? .markdown
        thinkingEnabled = try box.decodeIfPresent(Bool.self, forKey: .thinkingEnabled) ?? false
        // A chat written before P3 gets the chip **down**: tools are an opt-in, and a migration that
        // quietly armed a conversation the user never armed is the one outcome that would matter.
        toolToggle = try box.decodeIfPresent(ToolToggleSet.self, forKey: .toolToggle) ?? .off
        hybrid = try box.decodeIfPresent(HybridPlan.self, forKey: .hybrid)
    }
}
