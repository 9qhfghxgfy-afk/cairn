import Foundation

/// Which sampling knobs a server actually accepts.
///
/// The rule this type exists to enforce: **never send a key the server does not support.** A key a
/// server ignores is worse than a key it rejects, because the request succeeds and the user believes
/// the knob took effect. So the sheet may offer every knob, and the payload builder strips whatever
/// this table says the active kind cannot honour.
///
/// What is declared here is what the published wire formats document, not what a given build might
/// happen to accept. Anything not verifiable from this machine stays false and is recorded as such.
public struct SamplingSupport: Sendable, Equatable {
    public var temperature: Bool
    public var topP: Bool
    public var minP: Bool
    public var topK: Bool
    public var maxTokens: Bool
    public var repeatPenalty: Bool
    public var repeatLastN: Bool
    public var seed: Bool
    public var contextWindow: Bool

    public init(
        temperature: Bool = false,
        topP: Bool = false,
        minP: Bool = false,
        topK: Bool = false,
        maxTokens: Bool = false,
        repeatPenalty: Bool = false,
        repeatLastN: Bool = false,
        seed: Bool = false,
        contextWindow: Bool = false
    ) {
        self.temperature = temperature
        self.topP = topP
        self.minP = minP
        self.topK = topK
        self.maxTokens = maxTokens
        self.repeatPenalty = repeatPenalty
        self.repeatLastN = repeatLastN
        self.seed = seed
        self.contextWindow = contextWindow
    }

    public static let none = SamplingSupport()

    /// Every knob expressible — used by tests and by a backend that documents all of them.
    public static let all = SamplingSupport(
        temperature: true, topP: true, minP: true, topK: true, maxTokens: true,
        repeatPenalty: true, repeatLastN: true, seed: true, contextWindow: true
    )

    public func supports(_ key: SamplingKey) -> Bool {
        switch key {
        case .contextWindow: return contextWindow
        case .temperature: return temperature
        case .seed: return seed
        case .topP: return topP
        case .minP: return minP
        case .topK: return topK
        case .maxTokens: return maxTokens
        case .repeatPenalty: return repeatPenalty
        case .repeatLastN: return repeatLastN
        }
    }

    /// Knobs the user configured that this server cannot honour — the set the sheet warns about,
    /// because "your Top K is not reaching that server" has to be said out loud.
    public func droppedKeys(from config: SamplingConfig) -> [SamplingKey] {
        SamplingKey.allCases.filter { config.isConfigured($0) && !supports($0) }
    }
}

extension ServerProfileKind {
    /// The documented sampling surface of each kind.
    ///
    /// - **Ollama** (`/api/chat`, `options`): its documented options map covers every knob here —
    ///   `temperature`, `top_p`, `min_p`, `top_k`, `num_predict`, `repeat_penalty`,
    ///   `repeat_last_n`, `seed`, `num_ctx`.
    /// - **Ollama Cloud**: the same documented `options` map, since `ollama.com` publishes the
    ///   `/api/chat` shape. **Real-network unverified** — nothing has been sent to ollama.com from
    ///   this machine, so this row is the documentation, not an observation.
    /// - **OpenAI-compatible** (`/v1/chat/completions`): only the standard request fields. `min_p`,
    ///   `top_k`, `repeat_penalty`, `repeat_last_n` and any context-size field are *not* part of the
    ///   published schema, so they are never sent to a server that speaks only that schema — even
    ///   though some individual servers accept them privately.
    /// - **LM Studio**: its chat runs over the same OpenAI-compatible endpoint, so it gets the same
    ///   declared set. Whether its build accepts a non-standard extra is unverified here, and
    ///   declaring one would be a guess.
    public var samplingSupport: SamplingSupport {
        switch self {
        case .ollama, .ollamaCloud:
            return .all
        case .openAICompatible, .lmStudio:
            return SamplingSupport(
                temperature: true, topP: true, maxTokens: true, seed: true
            )
        }
    }
}
