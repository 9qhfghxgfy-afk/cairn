import CairnChatDomain
import Foundation

/// The question asked before an on-device model is loaded: does the memory this process still has
/// actually cover what this model will cost?
///
/// This is the gate a jetsam event is asking for. A 298 report on an 8 GB phone recorded 1,554 MiB
/// resident with 1,168 MiB of it dirty and unpurgeable, which is what happens when a load starts on a
/// measurement nobody took. A refused load costs one turn and says why in a sentence; an admitted
/// load that overruns the ceiling costs the conversation, because iOS takes the process — and the
/// message the person was writing with it.
///
/// What is counted, and why:
/// - **weights**, from the files on disk rather than a catalog's advertised number;
/// - **the attention cache at the bound Cairn actually runs** (`OnDeviceKV.tokenCap`), from the
///   model's own published `config.json` shape — the same estimator the Download tab warns with, so
///   the warning before a download and the gate before a load cannot disagree;
/// - **a Metal reserve** for shader pipelines, activations and the buffer pool the runtime keeps.
///
/// A model that publishes no attention shape gets no invented one: the gate falls back to one
/// blanket reserve large enough to stand for cache **and** pipelines, because an estimate built from a
/// guessed architecture is a false reassurance.
///
/// Every reading is a point in time. `os_proc_available_memory()` describes the moment it was asked,
/// so this runs at load time and is never cached, and a missing reading is **unknown, not unlimited**
/// — the rule `TwoResidentBudget` and `ResidentModelPolicy` already hold to.
public enum MLXLoadPreflight {
    /// Memory held back for Metal pipelines, activations and the runtime's buffer pool, counted
    /// alongside a cache this app can size from the model's published shape.
    public static let metalPipelineReserveBytes: Int64 = 128 * 1024 * 1024

    /// The stand-in when the attention cache cannot be sized: enough to cover a cache of unknown
    /// shape **and** the pipelines, so a model that publishes nothing is not charged less than one
    /// that publishes everything.
    public static let blanketReserveBytes: Int64 = 512 * 1024 * 1024

    /// What a load is expected to cost, saturating so an absurd catalog entry yields a large number
    /// rather than a wrap that reads as a fit.
    ///
    /// The attention shape arrives as plain numbers rather than a config struct because the caller
    /// reads them out of `config.json` and this function has to stay provable without a file.
    public static func requiredBytes(
        weightsBytes: Int64,
        layerCount: Int? = nil,
        kvHeadCount: Int? = nil,
        headDimension: Int? = nil,
        bytesPerElement: Int = 2,
        contextTokens: Int = OnDeviceKV.tokenCap,
        pipelineReserveBytes: Int64 = metalPipelineReserveBytes,
        blanketReserveBytes: Int64 = blanketReserveBytes
    ) -> Int64 {
        let weights = max(0, weightsBytes)
        guard let cache = MemoryFitEstimator.attentionCacheBytes(
            layerCount: layerCount,
            kvHeadCount: kvHeadCount,
            headDimension: headDimension,
            bytesPerElement: bytesPerElement,
            contextLength: contextTokens
        ) else {
            return saturatingAdd(weights, blanketReserveBytes)
        }
        return saturatingAdd(saturatingAdd(weights, cache), pipelineReserveBytes)
    }

    /// The gate itself. Unknown headroom and unmeasurable weights both refuse: this is a measured
    /// decision or it is nothing, and "we did not look" is not a licence to allocate.
    public static func decide(
        headroomBytes: Int64?,
        weightsBytes: Int64?,
        layerCount: Int? = nil,
        kvHeadCount: Int? = nil,
        headDimension: Int? = nil,
        bytesPerElement: Int = 2,
        contextTokens: Int = OnDeviceKV.tokenCap,
        pipelineReserveBytes: Int64 = metalPipelineReserveBytes,
        blanketReserveBytes: Int64 = blanketReserveBytes
    ) -> MLXLoadPreflightVerdict {
        guard let weights = weightsBytes, weights > 0 else {
            return .refuse(.weightsUnmeasurable)
        }
        let required = requiredBytes(
            weightsBytes: weights,
            layerCount: layerCount,
            kvHeadCount: kvHeadCount,
            headDimension: headDimension,
            bytesPerElement: bytesPerElement,
            contextTokens: contextTokens,
            pipelineReserveBytes: pipelineReserveBytes,
            blanketReserveBytes: blanketReserveBytes
        )
        guard let headroom = headroomBytes, headroom > 0 else {
            return .refuse(.headroomUnknown(requiredBytes: required))
        }
        let (usable, shareSaturated) = usableShareComponents(of: headroom)
        // A figure that arrived by saturating is the arithmetic giving up, not a measurement. An
        // absurd requirement reads as `Int64.max`, an absurd reading used to read as room for
        // anything, and the two together admitted the one load that cannot fit — so either one
        // refuses on its own. And a requirement the size of the whole reading may not pass either:
        // weights that consume every byte leave nothing for the process that is asking, so the
        // requirement has to sit strictly inside the reading as well as inside its usable share.
        guard !shareSaturated, required < Int64.max,
              required <= usable, required < headroom else {
            return .refuse(.headroomTooLow(requiredBytes: required, availableBytes: headroom))
        }
        return .admit(requiredBytes: required)
    }

    /// The share of a headroom reading a model may claim: four fifths, leaving a fifth for SwiftUI,
    /// the tokenizer, decoded images and everything else that shares this process with the model.
    /// One share rule app-wide — `MemoryFitEstimator`, `ResidentModelPolicy` and `TwoResidentBudget`
    /// read it from the same two numbers, so a decision can never be priced two ways.
    public static func usableShare(of headroomBytes: Int64) -> Int64 {
        usableShareComponents(of: headroomBytes).bytes
    }

    /// The same share, plus whether the arithmetic had to saturate. A saturated figure is a failure
    /// to measure, and the gate treats it as one rather than as room.
    private static func usableShareComponents(of headroomBytes: Int64)
        -> (bytes: Int64, saturated: Bool)
    {
        let numerator = Int64(MemoryFitEstimator.usableNumerator)
        let denominator = Int64(MemoryFitEstimator.usableDenominator)
        guard denominator > 0, numerator >= 0 else { return (Int64.max, true) }
        let whole = max(0, headroomBytes)
        // Divide before scaling. `(headroom / 5) * 4 + ((headroom % 5) * 4) / 5` is exactly
        // `floor(headroom * 4 / 5)`, but its largest product is four fifths of the input instead of
        // four times it, so `Int64.max` needs no clamp to be answered. The multiply-first form
        // overflowed on an absurd reading and then reported the overflow as "the whole of it is
        // room", which is how `Int64.max` of headroom came to admit any load at all.
        let (scaled, scaleOverflow) = (whole / denominator).multipliedReportingOverflow(by: numerator)
        let (tail, tailOverflow) = (whole % denominator).multipliedReportingOverflow(by: numerator)
        let (total, addOverflow) = scaled.addingReportingOverflow(tail / denominator)
        return (scaleOverflow || tailOverflow || addOverflow) ? (Int64.max, true) : (total, false)
    }

    private static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (total, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int64.max : total
    }
}
