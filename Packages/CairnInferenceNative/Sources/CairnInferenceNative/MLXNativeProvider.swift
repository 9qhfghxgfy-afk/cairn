import CairnChatDomain
import Foundation

/// On-device MLX as one of Cairn's engines.
///
/// Actor-wrapped at the boundary on purpose: the runtime it fronts is C++ with its own threading
/// rules, so nothing outside this actor may touch it. The app sees `InferenceProvider` and a
/// `NetworkClass` of `.onDevice`, which means no outbound badge and no opt-in — nothing here
/// sends a byte anywhere.
///
/// Reasoning is reported only when the model's own template emitted thinking markers; the parser
/// in `DeviceTemplateChunkParser` is what decides that, and a model that emits none produces a
/// turn with no thinking chunk.
public actor MLXNativeProvider: InferenceProvider {
    public static let engineID = "on-device.mlx"
    public static let modelID = "mlx-on-device"

    private let modelDirectory: URL?
    private var loaded: String?

    /// - Parameter modelDirectory: a folder of already-installed, already-verified weights.
    ///   Cairn's own downloader owns that folder; this engine never fetches anything.
    public init(modelDirectory: URL? = nil) {
        self.modelDirectory = modelDirectory
    }

    // MARK: - Identity (nonisolated so the registry can read them from any thread)

    public nonisolated var id: String { Self.engineID }
    public nonisolated var displayName: String { "On-Device (MLX)" }
    public nonisolated var networkClass: NetworkClass { .onDevice }
    public nonisolated var serverProfileID: UUID? { nil }
    public nonisolated var samplingSupport: SamplingSupport { .none }

    /// Weights on this phone, run by this app — which is what makes it a thing the chat's "On device"
    /// mode can route to. The runtime is C++ behind an actor; the kind is a plain declared value, so
    /// nothing about that boundary leaks into routing.
    public nonisolated var engineKind: EngineKind { .localModel }

    /// Nothing is claimed that the runtime has not been observed to emit. `thinking` is true
    /// because the templates can emit thinking markers, not because this model certainly does —
    /// the chunk parser, not this flag, decides whether a panel ever appears.
    public nonisolated var capabilities: ProviderCapabilities {
        ProviderCapabilities(
            streaming: true,
            thinking: true,
            toolCalling: true,
            vision: false,
            modelListing: true,
            modelPull: false,
            modelDelete: false,
            loadedModelInspection: true,
            contextLengthAdjustable: true
        )
    }

    public nonisolated var runtimeAvailability: NativeRuntimeAvailability {
        NativeRuntimeAvailability.current(hasInstalledModel: modelDirectory != nil)
    }

    public func models() async throws -> [ModelInfo] {
        [ModelInfo(id: Self.modelID, displayName: "Installed on-device model", providerID: id)]
    }

    /// Resident model, for the Running tab. `nil` until a turn has actually loaded one.
    public func residentModelId() -> String? { loaded }

    public nonisolated func stream(_ request: GenerationRequest) -> AsyncThrowingStream<StreamChunk, any Error> {
        let directory = modelDirectory
        let system = request.nativeSystemText
        let prompt = request.nativePromptText
        let started = ContinuousClock.now

        return AsyncThrowingStream { continuation in
            let work = Task {
                var parser = DeviceTemplateChunkParser()
                do {
                    guard let directory else { throw NativeGenerationError.modelNotInstalled }
                    try await MLXNativeEngine.generate(
                        system: system,
                        prompt: prompt,
                        modelDirectory: directory
                    ) { token in
                        if Task.isCancelled { return }
                        for chunk in parser.ingest(token) { continuation.yield(chunk) }
                    }
                    for chunk in parser.finish() { continuation.yield(chunk) }
                    continuation.yield(.metrics(GenerationMetrics(
                        tokensGenerated: 0,
                        elapsedSeconds: started.duration(to: .now).seconds,
                        finishReason: Task.isCancelled ? .cancelled : .stop
                    )))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }
}

private extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
