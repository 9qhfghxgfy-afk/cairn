import CairnChatDomain
import Foundation

/// The sampling values the on-device runtime is told to honour, and the claim that goes with them.
///
/// The support table and the resolved values live in one file because they are one fact: a knob listed
/// here is a knob the engine actually hands the runtime, and a knob that is not listed never reaches the
/// configuration sheet. A slider the runtime would ignore is worse than no slider — it teaches the user
/// that Cairn's settings do not mean anything.
///
/// `seed` is out: the runtime's generation parameters carry no seed, so a seed could only be honoured by
/// seeding a process-global generator, which is not this turn's to set. `contextWindow` is out too — the
/// runtime's `maxKVSize` is a rotating cache bound, not the window the model was trained for, and
/// offering it would promise a knob that changes something else.
struct NativeSampling: Sendable, Equatable {
    var maxTokens: Int?
    var temperature: Double?
    var topP: Double?
    var topK: Int?
    var minP: Double?
    var repeatPenalty: Double?
    var repeatLastN: Int?

    static let support = SamplingSupport(
        temperature: true, topP: true, minP: true, topK: true, maxTokens: true,
        repeatPenalty: true, repeatLastN: true,
        seed: false, contextWindow: false
    )

    /// The chat's own values, filtered to what this runtime honours. Values that stay nil stay nil: the
    /// runtime's defaults are its own, and Cairn inventing a temperature is how a turn stops being
    /// reproducible against the settings screen.
    static func resolve(_ sampling: SamplingConfig) -> NativeSampling {
        NativeSampling(
            maxTokens: sampling.maxTokens,
            temperature: sampling.temperature,
            topP: sampling.topP,
            topK: sampling.topK,
            minP: sampling.minP,
            repeatPenalty: sampling.repeatPenalty,
            repeatLastN: sampling.repeatLastN
        )
    }

    /// True when the user set nothing, which is the case where the runtime's defaults should stand.
    var isEmpty: Bool {
        maxTokens == nil && temperature == nil && topP == nil && topK == nil
            && minP == nil && repeatPenalty == nil && repeatLastN == nil
    }
}
