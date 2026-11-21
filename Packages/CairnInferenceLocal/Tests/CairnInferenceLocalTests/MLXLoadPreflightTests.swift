import CairnChatDomain
import Foundation
import Testing
@testable import CairnInferenceLocal

/// The gate that decides whether a model may be loaded at all.
///
/// What is pinned here is that every "yes" is a measurement. Unknown headroom, unmeasurable weights and
/// a tight reading all answer no, because a load that is refused costs one turn and says why, while a
/// load that is admitted and then overruns the ceiling costs the conversation — iOS takes the process,
/// and the message the person was writing goes with it.
struct MLXLoadPreflightTests {
    /// A 4-bit 4-billion-parameter build: about 1.07 GB of weights, 36 layers, 8 key-value heads, a
    /// 128-wide head. Every one of those numbers is published by the model itself, which is what makes
    /// the arithmetic below a measurement rather than a guess.
    private let weights: Int64 = 1_070_000_000
    private let layers = 36
    private let kvHeads = 8
    private let headDim = 128

    private func verdict(headroomBytes: Int64?, weightsBytes: Int64? = 1_070_000_000)
        -> MLXLoadPreflightVerdict
    {
        MLXLoadPreflight.decide(
            headroomBytes: headroomBytes,
            weightsBytes: weightsBytes,
            layerCount: layers,
            kvHeadCount: kvHeads,
            headDimension: headDim,
            contextTokens: OnDeviceKV.tokenCap
        )
    }

    @Test func theAttentionCacheIsPricedAtTheBoundTheEngineActuallyRuns() {
        // 2 × 36 × 8 × 128 × 2 bytes × 2,048 tokens: the cache for the **capped** window, not for the
        // 40k-token window the model advertises. That substitution is the whole difference between a
        // phone that survives a long conversation and one that does not.
        let cache = MemoryFitEstimator.attentionCacheBytes(
            layerCount: layers, kvHeadCount: kvHeads, headDimension: headDim,
            bytesPerElement: 2, contextLength: OnDeviceKV.tokenCap
        )
        #expect(cache == 301_989_888)
        let required = MLXLoadPreflight.requiredBytes(
            weightsBytes: weights, layerCount: layers, kvHeadCount: kvHeads,
            headDimension: headDim, contextTokens: OnDeviceKV.tokenCap
        )
        #expect(required == weights + (cache ?? 0) + MLXLoadPreflight.metalPipelineReserveBytes)
    }

    @Test func aModelThatPublishesNoAttentionShapeIsChargedABlanketReserveNotAGuess() {
        let shaped = MLXLoadPreflight.requiredBytes(
            weightsBytes: weights, layerCount: layers, kvHeadCount: kvHeads, headDimension: headDim
        )
        let blind = MLXLoadPreflight.requiredBytes(weightsBytes: weights)
        // The blanket figure has to stand for cache **and** pipelines, so a model that says nothing about
        // its own architecture is never cheaper than one that says everything.
        #expect(blind == weights + MLXLoadPreflight.blanketReserveBytes)
        #expect(blind > shaped)
    }

    @Test func unknownOrAbsurdHeadroomRefusesTheLoad() {
        #expect(verdict(headroomBytes: nil).isAdmitted == false)
        #expect(verdict(headroomBytes: 0).isAdmitted == false)
        #expect(verdict(headroomBytes: -1).isAdmitted == false)
        #expect((verdict(headroomBytes: nil).reasonText ?? "").isEmpty == false)
    }

    @Test func unmeasurableWeightsRefuseTheLoadWhateverTheHeadroomSays() {
        // "Could not size the files" is not a licence to allocate. A folder that cannot be read is a
        // phone mid-delete or out of storage, and both are the wrong moment to load a model.
        #expect(verdict(headroomBytes: 8_000_000_000, weightsBytes: nil).isAdmitted == false)
        #expect(verdict(headroomBytes: 8_000_000_000, weightsBytes: 0).isAdmitted == false)
    }

    @Test func theBoundaryIsTheUsableFourFifthsAndNotTheWholeReading() {
        let required = MLXLoadPreflight.requiredBytes(
            weightsBytes: weights, layerCount: layers, kvHeadCount: kvHeads, headDimension: headDim
        )
        // Exactly enough headroom, and one byte less of it. A gate that rounds toward "yes" is the gate
        // that gets the process taken partway through a load.
        let exactHeadroom = required * 5 / 4
        let admitted = verdict(headroomBytes: exactHeadroom)
        #expect(admitted.isAdmitted)
        #expect(verdict(headroomBytes: exactHeadroom - 1).isAdmitted == false)
        if case .admit(let priced) = admitted { #expect(priced == required) }
    }

    @Test func aTightReadingRefusesAndSaysWhatToDoAboutIt() {
        // 600 MB against a requirement of roughly 1.5 GB: the reading a phone gives after it has already
        // been squeezed, which is exactly when a load used to be started anyway.
        let text = verdict(headroomBytes: 600_000_000).reasonText ?? ""
        #expect(text.contains("Close other apps") || text.contains("smaller model"))
        // Sizes only — no path, no repository name, nothing naming which model was being loaded.
        #expect(!text.contains("config.json"))
    }

    @Test func anAbsurdRequirementSaturatesInsteadOfWrappingIntoAFit() {
        #expect(MLXLoadPreflight.requiredBytes(weightsBytes: Int64.max) == Int64.max)
        #expect(MLXLoadPreflight.decide(headroomBytes: Int64.max, weightsBytes: Int64.max).isAdmitted == false)
    }

    @Test func aRoomyReadingAdmitsTheModelATightOneRefused() {
        // The same model, the same shape, the same arithmetic, and a "yes" that is earned: 8 GB of
        // headroom is an eight-gigabyte phone with nothing else running.
        let admitted = verdict(headroomBytes: 8_000_000_000)
        #expect(admitted.isAdmitted)
        #expect(admitted.reasonText == nil)
    }
}
