import CairnChatDomain
import Foundation
import Testing
@testable import CairnInferenceLocal

struct OnDeviceModelRegistryTests {
    private func candidate(_ id: String, footprint: Int64) -> ResidentModel {
        ResidentModel(modelID: id, runtime: .mlx, weightsBytes: footprint,
                      footprintBytes: footprint, contextLength: 4096)
    }

    @Test func oneResidentThenEvict() async {
        let registry = OnDeviceModelRegistry(memory: FixedMemoryReading(bytes: 4_000_000_000))
        await registry.markLoaded(candidate("a", footprint: 1_000_000_000))
        #expect(await registry.residentModels().map(\.modelID) == ["a"])

        let decision = await registry.requestLoad(candidate("b", footprint: 1_000_000_000))
        #expect(decision == .evictThenAdmit(evict: ["a"]))

        await registry.markLoaded(candidate("b", footprint: 1_000_000_000), evicting: ["a"])
        #expect(await registry.residentModels().map(\.modelID) == ["b"])
    }

    @Test func unknownHeadroomNeverAdmitsASecondResident() async {
        let registry = OnDeviceModelRegistry(memory: FixedMemoryReading(bytes: nil))
        await registry.markLoaded(candidate("a", footprint: 1))
        let decision = await registry.requestLoad(
            candidate("b", footprint: 1), allowSecondResident: true
        )
        #expect(decision == .evictThenAdmit(evict: ["a"]))
    }

    @Test func memoryPressureUnloadsEverythingCairnOwns() async {
        let calls = Recorder()
        let registry = OnDeviceModelRegistry(
            memory: FixedMemoryReading(bytes: 8_000_000_000),
            unloader: { id in calls.record(id) }
        )
        await registry.markLoaded(candidate("a", footprint: 1))
        await registry.markLoaded(candidate("a", footprint: 1))
        let released = await registry.handleMemoryPressure()
        #expect(released == ["a"])
        #expect(calls.recorded == ["a"])
        #expect(await registry.residentModels().isEmpty)
    }

    @Test func explicitUnloadDropsOneModel() async {
        let registry = OnDeviceModelRegistry(memory: FixedMemoryReading(bytes: 4_000_000_000))
        await registry.markLoaded(candidate("a", footprint: 1))
        await registry.markUnloaded("a")
        #expect(await registry.isResident("a") == false)
    }
}

struct AppleModelAvailabilityTests {
    @Test func everyReasonSaysSomethingDifferent() {
        let reasons: [AppleModelAvailability] = [
            .available, .deviceNotEligible, .appleIntelligenceNotEnabled,
            .modelNotReady, .unsupportedOS, .frameworkAbsent,
        ]
        let texts = reasons.map(\.reasonText)
        #expect(Set(texts).count == reasons.count)
        #expect(texts.allSatisfy { !$0.isEmpty })
        #expect(reasons.filter(\.isUsable).count == 1)
    }

    @Test func appleRuntimeIsSystemManagedAndNeverTwoResidentByDefault() {
        #expect(OnDeviceRuntime.appleFoundationModels.lifecycleIsOurs == false)
        #expect(OnDeviceRuntime.mlx.lifecycleIsOurs)
    }
}

struct FoundationModelsProviderShapeTests {
    private let provider = FoundationModelsProvider()

    @Test func declaresOnlyWhatTheFrameworkActuallyDoes() {
        #expect(provider.id == FoundationModelsProvider.engineID)
        #expect(provider.networkClass == .onDevice)
        #expect(provider.serverProfileID == nil)
        #expect(provider.capabilities.streaming)
        #expect(provider.capabilities.thinking == false)
        #expect(provider.capabilities.toolCalling == false)
        #expect(provider.capabilities.vision == false)
        #expect(provider.capabilities.modelPull == false)
        #expect(provider.capabilities.modelDelete == false)
    }

    @Test func offersOneModelAndNoSamplingKnobs() async throws {
        let models = try await provider.models()
        #expect(models.count == 1)
        #expect(models.first?.providerID == provider.id)
    }

    @Test func systemBlockIsReadNotInvented() {
        let request = GenerationRequest(
            modelID: "m",
            messages: [
                ChatMessagePayload(role: .system, text: "Be brief."),
                ChatMessagePayload(role: .user, text: "Hi"),
                ChatMessagePayload(role: .assistant, text: "Hello"),
            ],
            config: ChatConfig()
        )
        #expect(request.systemText == "Be brief.")
        #expect(request.conversationText == "user: Hi\n\nassistant: Hello")
    }
}
