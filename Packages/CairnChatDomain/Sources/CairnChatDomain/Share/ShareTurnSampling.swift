import Foundation

/// The sampling knobs a client sent, read in the dialect it sent them in.
///
/// Ollama nests them under `options` and names them `num_predict` / `num_ctx`; the
/// OpenAI-compatible surface puts them at the top level and says `max_tokens`. Both spellings land
/// in the same `SamplingConfig`, which is the type the outbound encoder already knows how to filter
/// by engine: a key a client set but this engine does not read is dropped on the way out, exactly
/// as it is for a chat on this phone.
///
/// Only keys the dialect really defines are read. OpenAI's `frequency_penalty` is deliberately NOT
/// mapped onto Ollama's `repeat_penalty`. Two knobs with similar-sounding names and different
/// formulas are not the same knob, and inventing the equivalence would send a number the user never
/// set.
enum ShareTurnSampling {
    static func read(_ object: [String: JSONValue], dialect: ShareDialect) -> SamplingConfig {
        let source: [String: JSONValue] = dialect == .ollama
            ? (object["options"]?.dictionaryValue ?? [:])
            : object
        switch dialect {
        case .ollama:
            return SamplingConfig(
                temperature: source["temperature"]?.doubleValue,
                topP: source["top_p"]?.doubleValue,
                minP: source["min_p"]?.doubleValue,
                topK: source["top_k"]?.intValue,
                maxTokens: source["num_predict"]?.intValue,
                repeatPenalty: source["repeat_penalty"]?.doubleValue,
                repeatLastN: source["repeat_last_n"]?.intValue,
                seed: seedValue(source["seed"]),
                contextWindow: source["num_ctx"]?.intValue
            )
        case .openAI:
            return SamplingConfig(
                temperature: source["temperature"]?.doubleValue,
                topP: source["top_p"]?.doubleValue,
                topK: source["top_k"]?.intValue,
                // Newer clients say `max_completion_tokens` for the same knob and stop sending the
                // older name; reading only the older one ignores what the caller asked for.
                maxTokens: (source["max_tokens"] ?? source["max_completion_tokens"])?.intValue,
                seed: seedValue(source["seed"])
            )
        }
    }

    /// A number the client typed is a number the client owns, so it is the `fixed` mode and never
    /// Cairn's "I chose this" mode. Ollama's `-1` re-roll sentinel is not passed through either: a
    /// served turn that cannot be replayed is a turn whose node cannot be re-run.
    private static func seedValue(_ value: JSONValue?) -> SeedSetting? {
        guard let number = value?.intValue, number >= 0 else { return nil }
        return SeedSetting.fixed(number)
    }

    /// A client asking for reasoning, in the words its own dialect uses. This never invents a
    /// thinking panel. It only permits the engine to be asked.
    static func thinkingRequested(_ object: [String: JSONValue], dialect: ShareDialect) -> Bool {
        switch dialect {
        case .ollama:
            return object["options"]?.dictionaryValue?["thinking"]?.boolValue ?? false
        case .openAI:
            let effort = object["reasoning_effort"]?.textValue ?? ""
            return !effort.isEmpty && effort != "none"
        }
    }
}
