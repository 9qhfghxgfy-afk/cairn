import Foundation

/// Conservative footprint sizing: weights plus the attention cache for the **active** context,
/// not for the model's advertised maximum.
///
/// Cache bytes = `2 × layers × kv_heads × head_dim × bytes_per_element × context_length`, the 2
/// covering the key and value tensors. Every multiplier is saturating, so an absurd catalog entry
/// yields a large number rather than a trap.
public enum MemoryFitEstimator {
    /// The share of headroom a model may claim. A fifth of headroom stays with the app itself,
    /// because SwiftUI, the tokenizer and any decoded image live in the same process as the model.
    public static let usableNumerator = 4
    public static let usableDenominator = 5

    /// `nil` when the metadata cannot size the cache — reported, never guessed.
    public static func attentionCacheBytes(
        layerCount: Int?,
        kvHeadCount: Int?,
        headDimension: Int?,
        bytesPerElement: Int,
        contextLength: Int
    ) -> Int64? {
        guard let layers = layerCount, layers > 0,
              let heads = kvHeadCount, heads > 0,
              let dim = headDimension, dim > 0,
              bytesPerElement > 0, contextLength > 0
        else { return nil }

        var total = Int64(layers)
        for factor in [2, heads, dim, bytesPerElement, contextLength] {
            let (next, overflow) = total.multipliedReportingOverflow(by: Int64(factor))
            if overflow { return Int64.max }
            total = next
        }
        return total
    }

    /// Weights + cache where the metadata allows it, saturating. Without attention metadata the
    /// result is weights alone and `includesAttentionCache` is false, which the UI must say.
    public static func estimate(_ model: ModelWeightEstimate, contextLength: Int) -> MemoryEstimate {
        let weights = max(0, model.weightsBytes)
        guard let cache = attentionCacheBytes(
            layerCount: model.layerCount,
            kvHeadCount: model.kvHeadCount,
            headDimension: model.headDimension,
            bytesPerElement: model.bytesPerElement,
            contextLength: contextLength
        ) else {
            return MemoryEstimate(bytes: weights, includesAttentionCache: false)
        }
        let (total, overflow) = weights.addingReportingOverflow(cache)
        return MemoryEstimate(bytes: overflow ? Int64.max : total, includesAttentionCache: true)
    }

    public static func fit(
        _ model: ModelWeightEstimate,
        contextLength: Int,
        headroomBytes: Int64?
    ) -> MemoryFit {
        let estimate = self.estimate(model, contextLength: contextLength)
        guard let headroom = headroomBytes, headroom > 0 else {
            return .headroomUnknown(estimate: estimate)
        }

        let (scaled, overflow) = headroom.multipliedReportingOverflow(by: Int64(usableNumerator))
        let trusted = overflow ? headroom : scaled / Int64(usableDenominator)
        if estimate.bytes <= trusted { return .fits(estimate: estimate, headroomBytes: headroom) }
        if estimate.bytes <= headroom { return .tight(estimate: estimate, headroomBytes: headroom) }
        return .exceeds(estimate: estimate, headroomBytes: headroom)
    }
}
