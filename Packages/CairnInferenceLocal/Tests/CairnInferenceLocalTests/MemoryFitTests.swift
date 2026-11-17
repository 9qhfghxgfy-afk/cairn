import CairnChatDomain
import Testing
@testable import CairnInferenceLocal

struct MemoryFitTests {
    private let gptLike = ModelWeightEstimate(
        weightsBytes: 2_000_000_000,
        layerCount: 32,
        kvHeadCount: 8,
        headDimension: 128
    )

    @Test func attentionCacheUsesPublishedShape() {
        // 2 × 32 × 8 × 128 × 2 × 4096 = 536_870_912
        #expect(MemoryFitEstimator.attentionCacheBytes(
            layerCount: 32, kvHeadCount: 8, headDimension: 128,
            bytesPerElement: 2, contextLength: 4096
        ) == 536_870_912)
    }

    @Test func absentMetadataIsReportedNotInvented() {
        let bare = ModelWeightEstimate(weightsBytes: 1_000_000_000)
        let estimate = MemoryFitEstimator.estimate(bare, contextLength: 4096)
        #expect(estimate.bytes == 1_000_000_000)
        #expect(!estimate.includesAttentionCache)
    }

    @Test func doublingContextDoublesTheCache() {
        let short = MemoryFitEstimator.estimate(gptLike, contextLength: 4096)
        let long = MemoryFitEstimator.estimate(gptLike, contextLength: 8192)
        #expect(long.bytes > short.bytes)
        #expect(long.bytes - short.bytes == MemoryFitEstimator.attentionCacheBytes(
            layerCount: 32, kvHeadCount: 8, headDimension: 128,
            bytesPerElement: 2, contextLength: 4096
        ))
    }

    @Test func fitBandsAreOrdered() {
        let headroom: Int64 = 4_000_000_000
        #expect(MemoryFitEstimator.fit(gptLike, contextLength: 4096, headroomBytes: headroom)
            == .fits(estimate: MemoryFitEstimator.estimate(gptLike, contextLength: 4096),
                     headroomBytes: headroom))
        let tight = MemoryFitEstimator.fit(gptLike, contextLength: 40_960, headroomBytes: headroom)
        if case .exceeds = tight { } else { Issue.record("expected exceeds, got \(tight)") }
        #expect(tight.notice == "May exceed available device memory")
    }

    @Test func unknownHeadroomMakesNoPromise() {
        let fit = MemoryFitEstimator.fit(gptLike, contextLength: 4096, headroomBytes: nil)
        if case .headroomUnknown = fit { } else { Issue.record("expected headroomUnknown") }
        #expect(fit.notice == nil)
    }

    @Test func weightsOnlyEstimateSaysItIsWeightsOnly() {
        let fit = MemoryFitEstimator.fit(
            ModelWeightEstimate(weightsBytes: 9_000_000_000),
            contextLength: 4096,
            headroomBytes: 4_000_000_000
        )
        #expect(fit.notice == "May exceed available device memory")
        #expect(fit.precisionNotice == "Estimate covers model weights only")
    }

    @Test func absurdNumbersSaturateInsteadOfTrapping() {
        let huge = ModelWeightEstimate(
            weightsBytes: Int64.max / 2,
            layerCount: 1_000_000,
            kvHeadCount: 1_000_000,
            headDimension: 1_000_000
        )
        let estimate = MemoryFitEstimator.estimate(huge, contextLength: 1_000_000)
        #expect(estimate.bytes == Int64.max)
    }
}

struct ResidentModelPolicyTests {
    private func model(_ id: String, footprint: Int64) -> ResidentModel {
        ResidentModel(modelID: id, runtime: .mlx, weightsBytes: footprint,
                      footprintBytes: footprint, contextLength: 4096)
    }

    @Test func firstModelIsAdmitted() {
        #expect(ResidentModelPolicy.decide(current: [], candidate: model("a", footprint: 1_000_000),
                                           headroomBytes: 4_000_000) == .admit)
    }

    @Test func unknownHeadroomNeverAdmitsASecondResident() {
        let decision = ResidentModelPolicy.decide(
            current: [model("a", footprint: 1_000_000)],
            candidate: model("b", footprint: 1_000_000),
            headroomBytes: nil,
            allowSecondResident: true
        )
        #expect(decision == .evictThenAdmit(evict: ["a"]))
    }

    @Test func twoResidentsNeedRoomForBothInsideTheReserve() {
        let decision = ResidentModelPolicy.decide(
            current: [model("a", footprint: 1_000_000)],
            candidate: model("b", footprint: 800_000),
            headroomBytes: 4_000_000,
            allowSecondResident: true
        )
        #expect(decision == .admit)
    }

    @Test func defaultIsNeverTwoResident() {
        let decision = ResidentModelPolicy.decide(
            current: [model("a", footprint: 1)],
            candidate: model("b", footprint: 1),
            headroomBytes: Int64.max / 4
        )
        #expect(decision == .evictThenAdmit(evict: ["a"]))
    }

    @Test func candidateThatCannotFitAloneIsRefused() {
        let decision = ResidentModelPolicy.decide(
            current: [model("a", footprint: 1)],
            candidate: model("b", footprint: 5_000_000),
            headroomBytes: 4_000_000
        )
        #expect(decision == .refuse(.footprintBeyondHeadroom))
    }

    @Test func reloadingWhatIsAlreadyResidentChangesNothing() {
        #expect(ResidentModelPolicy.decide(current: [model("a", footprint: 1)],
                                           candidate: model("a", footprint: 1),
                                           headroomBytes: 10) == .admit)
    }
}
