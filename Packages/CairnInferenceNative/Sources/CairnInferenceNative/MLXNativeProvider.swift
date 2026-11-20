import CairnChatDomain
import Foundation

/// On-device MLX as one of Cairn's engines.
///
/// Actor-wrapped at the boundary on purpose: the runtime it fronts is C++ with its own threading rules,
/// so nothing outside this actor may touch it. The app sees `InferenceProvider` and a `NetworkClass` of
/// `.onDevice`, which means no outbound badge and no opt-in — nothing here sends a byte anywhere.
///
/// Reasoning is reported only when the model's own template emitted thinking markers; the parser in
/// `DeviceTemplateChunkParser` is what decides that, and a model that emits none produces a turn with no
/// thinking chunk. The same parser sits in front of the text the runtime produces, so a template that
/// marks a tool region is read there rather than shown.
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

    /// The knobs this engine actually hands the runtime, from the same table the engine reads — a slider
    /// the runtime would ignore is worse than no slider. See `NativeSampling`.
    public nonisolated var samplingSupport: SamplingSupport { NativeSampling.support }

    /// Weights on this phone, run by this app — which is what makes it a thing the chat's "On device"
    /// mode can route to. The runtime is C++ behind an actor; the kind is a plain declared value, so
    /// nothing about that boundary leaks into routing.
    public nonisolated var engineKind: EngineKind { .localModel }

    /// Nothing is claimed that the build cannot do. Tool calling is native here — schemas in, structured
    /// calls out — and it is offered only in a build that carries the runtime, because a build without it
    /// fails the turn before any tool is reached. `thinking` is true because the templates can emit
    /// thinking markers, not because this model certainly does; the chunk parser decides whether a panel
    /// ever appears. `contextLengthAdjustable` is false: the runtime generates into the window the model
    /// was trained for, and its `maxKVSize` is a cache bound, not a context the user can pick.
    public nonisolated var capabilities: ProviderCapabilities {
        ProviderCapabilities(
            streaming: true,
            thinking: true,
            toolCalling: MLXNativeEngine.isCompiledIn,
            vision: false,
            modelListing: true,
            modelPull: false,
            modelDelete: false,
            loadedModelInspection: true,
            contextLengthAdjustable: false
        )
    }

    public nonisolated var runtimeAvailability: NativeRuntimeAvailability {
        NativeRuntimeAvailability.current(hasInstalledModel: modelDirectory != nil)
    }

    public func models() async throws -> [ModelInfo] {
        [ModelInfo(id: Self.modelID, displayName: "Installed on-device model", providerID: id)]
    }

    /// Resident model, for the Running tab. `nil` until a turn has really started answering — claiming a
    /// model is in memory before the weights have been read would be a number the user then trusts.
    public func residentModelId() -> String? { loaded }

    public nonisolated func stream(
        _ request: GenerationRequest
    ) -> AsyncThrowingStream<StreamChunk, any Error> {
        let directory = modelDirectory
        return AsyncThrowingStream { continuation in
            let bridge = MLXStreamBridge(
                parser: DeviceTemplateChunkParser(offeredTools: request.tools),
                continuation: continuation
            ) { [weak self] in
                guard let self else { return }
                Task { await self.markResident() }
            }
            let work = Task {
                do {
                    guard let directory else { throw NativeGenerationError.modelNotInstalled }
                    try await MLXNativeEngine.stream(
                        request: request, modelDirectory: directory
                    ) { chunk in
                        bridge.receive(chunk)
                    }
                    bridge.complete()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                bridge.cancel()
                work.cancel()
            }
        }
    }

    private func markResident() { loaded = Self.modelID }
}
