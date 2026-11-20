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
    ///
    /// Each one names the effect, the direction, and what leaving it unset means — "lower is tighter" is
    /// worthless next to a number the user cannot place, and the unset case is the one Cairn adds rather
    /// than inherits.
    public var explainer: String {
        switch self {
        case .contextWindow:
            return "How much conversation the model keeps in working memory at once, including any text you "
                + "attach. A larger window costs more memory on the device or server and is capped by the "
                + "model itself; past the cap the oldest turns fall out. Left unset, the server uses the size "
                + "it was started with."
        case .temperature:
            return "How focused or creative an answer is. 0.0–0.3 picks predictable, factual phrasing; 0.8 and "
                + "above raises variety and creativity, and above roughly 1.5 more readily invents. Left "
                + "unset, the server's own value is used."
        case .seed:
            return "Locks the random number generator to one integer, so the same prompt with the same "
                + "settings produces the same answer again. Random means Cairn chose the number and still "
                + "sends it every turn, so a replay repeats; Fixed means you typed it and Cairn will not "
                + "change it. Left unset, no seed is sent and the server chooses."
        case .topP:
            return "Nucleus sampling: keeps the smallest group of candidate words whose probabilities add up "
                + "to this much and drops the rest. Lower is tighter and safer; 1.00 leaves the whole "
                + "vocabulary in play. Left unset, the server's own value is used."
        case .minP:
            return "Drops any candidate whose probability falls below this share of the top choice, which "
                + "cuts off unlikely nonsense without over-restricting creative phrasing. 0.00 keeps "
                + "everything. Left unset, the server's own value is used."
        case .topK:
            return "Caps each step to only the K most likely next words. Smaller is a tighter focus; larger "
                + "lets a wider vocabulary back in. Left unset, the server's own value is used."
        case .maxTokens:
            return "The most a single reply may produce, after which generation stops. Unlimited sends no "
                + "limit at all, so the server answers until it finishes or reaches a ceiling of its own."
        case .repeatPenalty:
            return "Discourages the model from saying again what it has already said. 1.00 applies no "
                + "penalty; above that a word already used becomes less likely, and set too high a long "
                + "answer starts avoiding the words it needs. Left unset, the server's own value is used."
        case .repeatLastN:
            return "How many of the most recent tokens the repeat penalty looks back over when checking for "
                + "repetition. Left unset, the server's own value is used."
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
