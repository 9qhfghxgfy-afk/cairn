import Foundation

/// One sampling knob, named once. The sheet, the capability table, the payload builder, and the
/// `(i)` copy all go through this list, so a knob cannot be configurable in one place and
/// unsupported in another.
public enum SamplingKey: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
    case contextWindow
    case temperature
    case seed
    case topP
    case minP
    case topK
    case maxTokens
    case repeatPenalty
    case repeatLastN

    public var id: String { rawValue }

    /// Order matters: `allCases` is the display order in the sheet (the three headline controls
    /// first, then the collapsed Advanced group) and the emit order in the payload.
    public static let headlineKeys: [SamplingKey] = [.contextWindow, .temperature, .seed]
    public static let advancedKeys: [SamplingKey] =
        [.topP, .minP, .topK, .maxTokens, .repeatPenalty, .repeatLastN]

    public var displayName: String {
        switch self {
        case .contextWindow: return "Context Size"
        case .temperature: return "Temperature"
        case .seed: return "Seed"
        case .topP: return "Top P"
        case .minP: return "Min P"
        case .topK: return "Top K"
        case .maxTokens: return "Max Tokens"
        case .repeatPenalty: return "Repeat Penalty"
        case .repeatLastN: return "Repeat Last N"
        }
    }

    /// The `(i)` popover text. Written here so the sheet and any later help screen cannot
    /// disagree about what a knob does.
    public var explainer: String {
        switch self {
        case .contextWindow:
            return "How much of the conversation the model can see at once. Larger costs more "
                + "memory on the server and is capped by the model itself. Left unset, the server "
                + "uses the size it was started with."
        case .temperature:
            return "How adventurous the next word is. 0.00 is the most predictable, 2.00 the most "
                + "surprising. Left unset, the server's own value is used."
        case .seed:
            return "The starting point for sampling. The same seed with the same settings reproduces "
                + "the same answer. Left unset, no seed is sent and the server chooses."
        case .topP:
            return "Nucleus sampling: the smallest set of candidate words whose probabilities add up "
                + "to this much. Left unset, the server's own value is used."
        case .minP:
            return "Drops any candidate whose probability falls below this share of the best "
                + "candidate. 0.00 keeps everything. Left unset, the server's own value is used."
        case .topK:
            return "Considers only this many best candidate words at each step. Left unset, the "
                + "server's own value is used."
        case .maxTokens:
            return "The most words this reply may produce. Unlimited sends nothing, so the server "
                + "answers until it finishes or hits its own ceiling."
        case .repeatPenalty:
            return "Discourages repeating what has already been said. 1.00 applies no penalty. "
                + "Left unset, the server's own value is used."
        case .repeatLastN:
            return "How far back the repeat penalty looks, in tokens. Left unset, the server's own "
                + "value is used."
        }
    }

    public func isSet(in config: SamplingConfig) -> Bool {
        switch self {
        case .contextWindow: return config.contextWindow != nil
        case .temperature: return config.temperature != nil
        case .seed: return config.seed != nil
        case .topP: return config.topP != nil
        case .minP: return config.minP != nil
        case .topK: return config.topK != nil
        case .maxTokens: return config.maxTokens != nil
        case .repeatPenalty: return config.repeatPenalty != nil
        case .repeatLastN: return config.repeatLastN != nil
        }
    }

    public func clear(in config: inout SamplingConfig) {
        switch self {
        case .contextWindow: config.contextWindow = nil
        case .temperature: config.temperature = nil
        case .seed: config.seed = nil
        case .topP: config.topP = nil
        case .minP: config.minP = nil
        case .topK: config.topK = nil
        case .maxTokens: config.maxTokens = nil
        case .repeatPenalty: config.repeatPenalty = nil
        case .repeatLastN: config.repeatLastN = nil
        }
    }
}
