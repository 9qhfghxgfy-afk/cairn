import Foundation

/// What a model's own `config.json` says about its attention shape, context, and capabilities.
///
/// These are the keys an MLX-converted repository publishes. Every lookup is optional and the
/// reader adds nothing: a model that does not state `num_key_value_heads` gets no cache estimate,
/// not a default one, because a made-up head count turns a memory warning into a false reassurance.
///
/// `head_dim` is often absent; when it is, `hidden_size / num_attention_heads` is the documented
/// identity for these architectures, so it is derived — not guessed — and only when both operands
/// were themselves stated.
public struct ModelConfigFacts: Sendable, Equatable {
    public var layerCount: Int?
    public var kvHeadCount: Int?
    public var headDimension: Int?
    public var contextLength: Int?
    public var capabilities: [ModelCapability]

    public init(
        layerCount: Int? = nil,
        kvHeadCount: Int? = nil,
        headDimension: Int? = nil,
        contextLength: Int? = nil,
        capabilities: [ModelCapability] = []
    ) {
        self.layerCount = layerCount
        self.kvHeadCount = kvHeadCount
        self.headDimension = headDimension
        self.contextLength = contextLength
        self.capabilities = capabilities
    }

    public var weightEstimate: ModelWeightEstimate {
        ModelWeightEstimate(
            weightsBytes: 0,
            layerCount: layerCount,
            kvHeadCount: kvHeadCount,
            headDimension: headDimension
        )
    }
}

public enum ModelConfigReader {
    public static func read(_ data: Data) -> ModelConfigFacts {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ModelConfigFacts()
        }
        return read(from: object)
    }

    public static func read(from object: [String: Any]) -> ModelConfigFacts {
        let heads = integer(object["num_attention_heads"])
        let hidden = integer(object["hidden_size"])
        let headDim = integer(object["head_dim"])
            ?? quotient(hidden, heads)

        return ModelConfigFacts(
            layerCount: integer(object["num_hidden_layers"]) ?? integer(object["n_layer"]),
            kvHeadCount: integer(object["num_key_value_heads"]) ?? heads,
            headDimension: headDim,
            contextLength: integer(object["max_position_embeddings"])
                ?? integer(object["n_positions"])
                ?? integer(object["model_max_length"]),
            capabilities: CapabilityReader.read(from: object)
        )
    }

    static func integer(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String, let parsed = Int(text) { return parsed }
        return nil
    }

    /// Derived only when both operands were published, and never when it would round to zero.
    static func quotient(_ numerator: Int?, _ denominator: Int?) -> Int? {
        guard let numerator, let denominator, denominator > 0 else { return nil }
        let result = numerator / denominator
        return result > 0 ? result : nil
    }
}
