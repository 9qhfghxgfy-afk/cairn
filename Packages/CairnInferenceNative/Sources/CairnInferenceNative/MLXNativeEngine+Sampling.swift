import CairnChatDomain
import Foundation

#if !targetEnvironment(simulator) && canImport(MLXLMCommon)
import MLXLMCommon

/// Where Cairn's chat settings meet the runtime's parameters, and where the runtime's report becomes
/// Cairn's metric. Kept apart from the streaming loop so both halves can be read on their own.
extension MLXNativeEngine {
    /// Only what the chat set is passed; the runtime's own defaults stand for everything else. Writing
    /// Cairn's idea of a sensible temperature into every turn would make a chat unreproducible against its
    /// own settings screen.
    ///
    /// One value is always set and never comes from the chat: the attention-cache bound. It is the
    /// difference between a KV cache that grows with a conversation until iOS takes the process and one
    /// that stops at a stated size, and it is not a knob the user is offered — see `NativeSampling`.
    static func parameters(for request: GenerationRequest) -> GenerateParameters {
        let chosen = NativeSampling.resolve(request.config.sampling)
        var parameters = GenerateParameters()
        parameters.maxKVSize = NativeSampling.kvBound()
        if let value = chosen.maxTokens { parameters.maxTokens = value }
        if let value = chosen.temperature { parameters.temperature = Float(value) }
        if let value = chosen.topP { parameters.topP = Float(value) }
        if let value = chosen.topK { parameters.topK = value }
        if let value = chosen.minP { parameters.minP = Float(value) }
        if let value = chosen.repeatPenalty { parameters.repetitionPenalty = Float(value) }
        if let value = chosen.repeatLastN { parameters.repetitionContextSize = value }
        return parameters
    }

    /// Reported, never estimated. No `.info` event means the runtime never said why it stopped, and
    /// `.unknown` is the honest answer to that; a cancelled turn says so even when the runtime reported a
    /// stop for the tokens it had already produced.
    static func finishReason(
        info: GenerateCompletionInfo?, cancelled: Bool
    ) -> FinishReason {
        if cancelled { return .cancelled }
        switch info?.stopReason {
        case .stop: return .stop
        case .length: return .length
        case .cancelled: return .cancelled
        case .none: return .unknown
        }
    }
}
#endif
