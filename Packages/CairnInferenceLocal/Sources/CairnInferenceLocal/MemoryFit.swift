import Foundation

/// The shape of one on-device model, as far as memory sizing is concerned.
///
/// `weightsBytes` comes from the catalog's published size or from the files on disk. The attention
/// fields come from the model's own published metadata — its `config.json` once downloaded. A field
/// that is absent stays `nil` and the estimate is reported as weights-only: the estimator never
/// invents an architecture to make its own arithmetic look complete.
public struct ModelWeightEstimate: Sendable, Equatable {
    public var weightsBytes: Int64
    public var layerCount: Int?
    public var kvHeadCount: Int?
    public var headDimension: Int?
    /// Bytes per cached value: 2 for fp16/bf16, 1 for an 8-bit cache, 4 for fp32.
    public var bytesPerElement: Int

    public init(
        weightsBytes: Int64,
        layerCount: Int? = nil,
        kvHeadCount: Int? = nil,
        headDimension: Int? = nil,
        bytesPerElement: Int = 2
    ) {
        self.weightsBytes = weightsBytes
        self.layerCount = layerCount
        self.kvHeadCount = kvHeadCount
        self.headDimension = headDimension
        self.bytesPerElement = max(1, bytesPerElement)
    }

    /// True when the metadata is complete enough to size the attention cache at all.
    public var canSizeAttention: Bool {
        (layerCount ?? 0) > 0 && (kvHeadCount ?? 0) > 0 && (headDimension ?? 0) > 0
    }
}

/// One footprint figure, and whether it includes the attention cache or weights alone.
public struct MemoryEstimate: Sendable, Equatable {
    public var bytes: Int64
    /// False means weights only: a floor, not a promise. The UI says so instead of implying the
    /// whole footprint was measured.
    public var includesAttentionCache: Bool

    public init(bytes: Int64, includesAttentionCache: Bool) {
        self.bytes = bytes
        self.includesAttentionCache = includesAttentionCache
    }
}

/// Whether a model is expected to fit in the memory actually available to this process.
public enum MemoryFit: Sendable, Equatable {
    case fits(estimate: MemoryEstimate, headroomBytes: Int64)
    /// Inside the ceiling, but with too little margin to trust under pressure.
    case tight(estimate: MemoryEstimate, headroomBytes: Int64)
    case exceeds(estimate: MemoryEstimate, headroomBytes: Int64)
    /// The platform gave no headroom figure, so no promise can be made either way.
    case headroomUnknown(estimate: MemoryEstimate)

    public var estimate: MemoryEstimate {
        switch self {
        case .fits(let e, _), .tight(let e, _), .exceeds(let e, _), .headroomUnknown(let e):
            return e
        }
    }

    /// The UI shows this verbatim on the Download tab. It is a warning, never a block: the user
    /// may still try, and a load failure then reports itself honestly.
    public var notice: String? {
        switch self {
        case .fits, .headroomUnknown:
            return nil
        case .tight, .exceeds:
            return "May exceed available device memory"
        }
    }

    /// Shown alongside the notice when only the weights could be counted.
    public var precisionNotice: String? {
        estimate.includesAttentionCache ? nil : "Estimate covers model weights only"
    }
}
