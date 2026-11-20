import CairnChatDomain
import Foundation
import Testing

@testable import CairnInferenceNative

/// The provider is a boundary, and a boundary has to hold even on a machine with no Metal and in
/// a build that left the runtime out. These tests run on the macOS host with the runtime absent,
/// which is exactly the case that must not crash, hang, or pretend.
struct MLXNativeProviderTests {
    private func request() -> GenerationRequest {
        GenerationRequest(
            modelID: MLXNativeProvider.modelID,
            messages: [
                ChatMessagePayload(role: .system, text: "Be brief."),
                ChatMessagePayload(role: .user, text: "Hello"),
            ],
            config: ChatConfig()
        )
    }

    @Test func conformsToTheOneProviderProtocol() async throws {
        let provider: any InferenceProvider = MLXNativeProvider()
        #expect(provider.id == "on-device.mlx")
        #expect(provider.networkClass == .onDevice)
        // An on-device engine never needs the outbound opt-in and never earns the badge.
        #expect(!provider.networkClass.requiresOptIn)
        #expect(!provider.networkClass.leavesTheDevice)
        #expect(provider.serverProfileID == nil)
        let models = try await provider.models()
        #expect(models.count == 1)
    }

    @Test func onlyKnobsTheEngineHonestToTheRuntimeAreOffered() {
        // The config sheet renders from this table, so a true row has to be a value the engine really
        // hands the runtime — and a knob the runtime's own parameters do not carry stays false, which is
        // the case where a slider would teach the user that Cairn's settings mean nothing.
        let support = MLXNativeProvider().samplingSupport
        #expect(support == NativeSampling.support)
        #expect(support.temperature && support.topP && support.minP && support.topK)
        #expect(support.maxTokens && support.repeatPenalty && support.repeatLastN)
        #expect(!support.seed && !support.contextWindow)
    }

    @Test func availabilityIsDerivedFromTheBuildRatherThanAsserted() {
        let linked = NativeRuntimeBuild.mlxIsLinked
        let simulator = NativeRuntimeBuild.isSimulatorBuild
        let state = NativeRuntimeAvailability.current(hasInstalledModel: true)
        if !linked {
            #expect(state == .excludedFromThisBuild)
        } else if simulator {
            #expect(state == .unavailableOnSimulator)
        } else {
            #expect(state == .ready)
        }
        // Nothing may call this "ready" while the runtime is not in the binary.
        if !linked { #expect(!state.isUsable) }
    }

    @Test func missingModelIsReportedAsAMissingModelNotASecretFailure() async {
        let provider = MLXNativeProvider(modelDirectory: nil)
        var thrown: NativeGenerationError?
        do {
            for try await _ in provider.stream(request()) {}
        } catch let issue as NativeGenerationError {
            thrown = issue
        } catch {
            Issue.record("unexpected error type: \(type(of: error))")
        }
        #expect(thrown == .modelNotInstalled)
    }

    @Test func runtimeWithoutAMetalDeviceFailsTypedAndNeverHangs() async throws {
        guard !NativeRuntimeBuild.mlxIsLinked || NativeRuntimeBuild.isSimulatorBuild else { return }
        let here = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("absent")
        let provider = MLXNativeProvider(modelDirectory: here)
        var thrown: NativeGenerationError?
        do {
            for try await _ in provider.stream(request()) {}
        } catch let issue as NativeGenerationError {
            thrown = issue
        }
        #expect(thrown == .runtimeUnavailableOnSimulator || thrown == .runtimeExcludedFromThisBuild)
    }

    @Test func nothingIsResidentUntilATurnActuallyLoadsSomething() async {
        let provider = MLXNativeProvider()
        #expect(await provider.residentModelId() == nil)
    }

    @Test func promptFlatteningKeepsOneSystemBlockAndNothingInvented() {
        let flat = request()
        #expect(flat.nativeSystemText == "Be brief.")
        #expect(flat.nativePromptText == "user: Hello")
    }
}
