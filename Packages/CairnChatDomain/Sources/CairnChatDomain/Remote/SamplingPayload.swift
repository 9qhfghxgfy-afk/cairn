import Foundation

/// Which wire dialect a sampling value is being written for. Named by dialect rather than by
/// server kind because LM Studio and any OpenAI-compatible server share one request shape, and
/// Ollama and Ollama Cloud share another.
public enum SamplingDialect: String, Sendable, Equatable, CaseIterable {
    case ollama
    case openAI
}

/// One key/value pair destined for a request body.
public struct SamplingField: Sendable, Equatable {
    public var key: String
    public var value: SamplingValue

    public init(key: String, value: SamplingValue) {
        self.key = key
        self.value = value
    }
}

/// A JSON key that is not known at compile time. Both dialects name their sampling keys in
/// snake_case, which Swift's synthesised `CodingKey` would mangle, and the keys are decided by the
/// capability table at run time.
public struct DynamicCodingKey: CodingKey {
    public var stringValue: String
    public var intValue: Int?

    public init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    public init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

/// The sampling keys of a request, in one place.
///
/// Two rules, and nothing else: a knob that is unset produces no field, and a knob the server does
/// not support produces no field. Encoders then have no sampling logic left to get wrong.
public enum SamplingPayload {
    /// The wire name for one knob in one dialect, or `nil` when that dialect has no such field.
    public static func wireKey(_ key: SamplingKey, dialect: SamplingDialect) -> String? {
        switch (key, dialect) {
        case (.temperature, .ollama), (.temperature, .openAI): return "temperature"
        case (.topP, .ollama), (.topP, .openAI): return "top_p"

        case (.contextWindow, .ollama): return "num_ctx"
        case (.seed, .ollama), (.seed, .openAI): return "seed"
        case (.maxTokens, .ollama): return "num_predict"
        case (.maxTokens, .openAI): return "max_tokens"
        case (.topK, .ollama): return "top_k"
        case (.minP, .ollama): return "min_p"
        case (.repeatPenalty, .ollama): return "repeat_penalty"
        case (.repeatLastN, .ollama): return "repeat_last_n"

        // The OpenAI schema publishes none of these; emitting them would be a key the server
        // accepts and then ignores, which is the failure this table exists to prevent.
        case (.contextWindow, .openAI), (.topK, .openAI), (.minP, .openAI),
             (.repeatPenalty, .openAI), (.repeatLastN, .openAI):
            return nil
        }
    }

    /// Fields for a request, already filtered and named. Order follows `SamplingKey.allCases`, so
    /// two runs of the same configuration build byte-identical bodies.
    public static func fields(
        sampling: SamplingConfig,
        support: SamplingSupport,
        dialect: SamplingDialect
    ) -> [SamplingField] {
        SamplingKey.allCases.compactMap { key in
            guard support.supports(key), let raw = value(for: key, in: sampling) else { return nil }
            guard let name = wireKey(key, dialect: dialect) else { return nil }
            return SamplingField(key: name, value: raw)
        }
    }

    /// The value for one knob in the type its wire wants: counts and indices are integers, the
    /// probabilities and penalties are floats.
    public static func value(for key: SamplingKey, in sampling: SamplingConfig) -> SamplingValue? {
        switch key {
        case .contextWindow: return sampling.contextWindow.map { SamplingValue.int($0) }
        case .temperature: return sampling.temperature.map { SamplingValue.double($0) }
        case .seed: return sampling.seed.map { SamplingValue.int($0.value) }
        case .topP: return sampling.topP.map { SamplingValue.double($0) }
        case .minP: return sampling.minP.map { SamplingValue.double($0) }
        case .topK: return sampling.topK.map { SamplingValue.int($0) }
        case .maxTokens: return sampling.maxTokens.map { SamplingValue.int($0) }
        case .repeatPenalty: return sampling.repeatPenalty.map { SamplingValue.double($0) }
        case .repeatLastN: return sampling.repeatLastN.map { SamplingValue.int($0) }
        }
    }
}

/// An ordered set of sampling fields that encodes as a JSON object with the keys it was given.
public struct SamplingFieldList: Sendable, Equatable {
    public var fields: [SamplingField]

    public init(fields: [SamplingField] = []) {
        self.fields = fields
    }

    public init(
        sampling: SamplingConfig,
        support: SamplingSupport,
        dialect: SamplingDialect
    ) {
        self.fields = SamplingPayload.fields(sampling: sampling, support: support, dialect: dialect)
    }

    public var isEmpty: Bool { fields.isEmpty }

    /// Writes the fields into an existing keyed container, which is how the OpenAI body keeps its
    /// own fixed keys and still gets sampling added to the top level.
    public func encode(
        into container: inout KeyedEncodingContainer<DynamicCodingKey>
    ) throws {
        for field in fields {
            try container.encode(field.value, forKey: DynamicCodingKey(stringValue: field.key))
        }
    }
}

extension SamplingFieldList: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        for field in fields {
            try container.encode(field.value, forKey: DynamicCodingKey(stringValue: field.key))
        }
    }
}
