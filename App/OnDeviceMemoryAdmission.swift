import CairnChatDomain
import CairnInferenceLocal
import CairnInferenceNative
import Foundation

/// The measured gate in front of every on-device MLX load.
///
/// This is the seam between the two halves of the problem. The arithmetic that decides whether a model
/// fits (`MLXLoadPreflight`, `MLXMemoryBudget`) is pure and provable; the code that spends the memory is
/// the Swift 5 island that imports MLX and cannot be tested where the arithmetic can. The app owns the
/// only thing both halves need — the model store, which is where a model's size on disk actually comes
/// from — so the gate is built here and handed across.
///
/// Two readings are taken at load time and neither is cached: what the files on disk weigh, and what
/// `os_proc_available_memory()` says this process still has. A headroom figure describes the moment it
/// was read, so a turn that was allowed an hour ago has no claim on this one.
struct OnDeviceMemoryAdmission: NativeMemoryAdmitting {
    private let registry: OnDeviceModelRegistry
    private let memory: any MemoryReading
    private let footprint: @Sendable (URL) -> MLXModelFootprint?

    init(
        registry: OnDeviceModelRegistry,
        memory: any MemoryReading = SystemMemoryReading(),
        footprint: @escaping @Sendable (URL) -> MLXModelFootprint? = { url in
            MLXModelDiscovery.footprint(at: url)
        }
    ) {
        self.registry = registry
        self.memory = memory
        self.footprint = footprint
    }

    func admitLoading(modelDirectory: URL) async -> NativeAdmission {
        let measured = footprint(modelDirectory)
        let headroom = memory.availableMemoryBytes()
        let verdict = MLXLoadPreflight.decide(
            headroomBytes: headroom,
            weightsBytes: measured?.weightsBytes,
            layerCount: measured?.layerCount,
            kvHeadCount: measured?.kvHeadCount,
            headDimension: measured?.headDimension,
            contextTokens: OnDeviceKV.tokenCap
        )
        switch verdict {
        case .refuse(let refusal):
            // The refusal's own sentence, carried across unchanged. It was written from the measurement
            // that produced it, and a gate that rewords its own numbers stops being a measurement.
            return .refuse(reason: refusal.reasonText)
        case .admit(let requiredBytes):
            return await admitResident(modelDirectory: modelDirectory, requiredBytes: requiredBytes, headroom: headroom)
        }
    }

    /// The turn is over, so the model is idle and any release deferred under it can land.
    func turnFinished(modelDirectory: URL) async {
        await registry.markIdle(MLXNativeProvider.modelID)
    }

    /// Records this model as the resident one, applying whatever eviction the registry's own single-
    /// resident rule calls for. Eviction goes through the injected unloader, so the other runtime really
    /// gives its memory back before this one asks for more.
    private func admitResident(
        modelDirectory: URL,
        requiredBytes: Int64,
        headroom: Int64?
    ) async -> NativeAdmission {
        let decision = await registry.beginTurn(with: ResidentModel(
            modelID: MLXNativeProvider.modelID,
            runtime: .mlx,
            weightsBytes: footprint(modelDirectory)?.weightsBytes ?? 0,
            footprintBytes: requiredBytes,
            contextLength: OnDeviceKV.tokenCap
        ))
        switch decision {
        case .refuse(let refusal):
            return .refuse(reason: refusal.reasonText)
        case .admit, .evictThenAdmit:
            return .admit(cacheLimitBytes: MLXMemoryBudget.cacheLimitBytes(headroomBytes: headroom))
        }
    }
}
