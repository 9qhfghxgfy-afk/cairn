import Foundation
import CairnChatDomain

/// The pre-P2 knob blob, read back as a configuration.
///
/// `SamplingParams` stored every knob as a mandatory value, so a row written before P2 asserted
/// temperature, top_p, repeat penalty, max tokens and context window on **every** turn. Reading those
/// back as configured overrides is what keeps an existing chat answering the same way after the
/// upgrade instead of silently dropping to whatever the server defaults to.
///
/// This type exists only here, and only for reading. Nothing writes it, and the domain never sees it.
struct LegacyChatConfig {
    private struct LegacyBlob: Decodable {
        var temperature: Double?
        var topP: Double?
        var repeatPenalty: Double?
        var maxTokens: Int?
        var contextWindow: Int?
        var thinkingEnabled: Bool?
        var systemPrompt: String?
    }

    /// An unreadable or empty blob becomes `ChatConfig.bare`: no knob asserted, nothing injected —
    /// which is the honest reading of a row whose settings cannot be recovered.
    static func upgrade(from data: Data?) -> ChatConfig {
        guard let legacy = JSONCodec.decode(LegacyBlob.self, from: data) else { return .bare }
        return ChatConfig(
            persona: legacy.systemPrompt ?? "",
            sampling: SamplingConfig(
                temperature: legacy.temperature,
                topP: legacy.topP,
                maxTokens: legacy.maxTokens,
                repeatPenalty: legacy.repeatPenalty,
                contextWindow: legacy.contextWindow
            ),
            // A pre-P2 chat injected nothing but its own system prompt. Upgrading it must not start
            // adding date, device or capability lines to a conversation the user already had — that
            // changes answers behind their back. A chat that wants injections turns them on.
            context: .off,
            responseFormat: .markdown,
            thinkingEnabled: legacy.thinkingEnabled ?? false
        )
    }
}
