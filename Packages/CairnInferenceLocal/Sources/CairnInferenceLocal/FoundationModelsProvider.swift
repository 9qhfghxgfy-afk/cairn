import CairnChatDomain
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's system-managed on-device model, as one of the engines Cairn can talk to.
///
/// Nothing here is downloaded and nothing is unloaded: Apple installs and evicts this model, so the
/// Running tab reports it rather than offering controls for it (Finding F5). Availability is read at
/// the moment of use and its exact reason is surfaced, never folded into a generic failure.
///
/// Reasoning is emitted only if the framework hands Cairn a thinking field. It does not, so this
/// provider emits `.content` and `.metrics` and nothing else — no reasoning panel appears for it,
/// because a panel full of invented "reasoning" is worse than no panel.
public struct FoundationModelsProvider: InferenceProvider {
    public static let engineID = "on-device.apple"
    public static let modelID = "apple-on-device"

    public init() {}

    public var id: String { Self.engineID }
    public var displayName: String { "On-Device (Apple)" }
    public var networkClass: NetworkClass { .onDevice }
    public var serverProfileID: UUID? { nil }
    public var samplingSupport: SamplingSupport { .none }

    /// Declared, not hoped for: no thinking field, no tool calls, no vision, and no sampling knobs
    /// this API reads. A knob the framework would silently ignore must not appear in the sheet.
    public var capabilities: ProviderCapabilities {
        ProviderCapabilities(
            streaming: true,
            thinking: false,
            toolCalling: false,
            vision: false,
            modelListing: true,
            modelPull: false,
            modelDelete: false,
            loadedModelInspection: false,
            contextLengthAdjustable: false
        )
    }

    public func models() async throws -> [ModelInfo] {
        [ModelInfo(id: Self.modelID, displayName: "Apple on-device model", providerID: id)]
    }

    public func stream(_ request: GenerationRequest) -> AsyncThrowingStream<StreamChunk, any Error> {
        AsyncThrowingStream { continuation in
            let work = Task {
                do {
                    try await Self.generate(request, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    private static func generate(
        _ request: GenerationRequest,
        into continuation: AsyncThrowingStream<StreamChunk, any Error>.Continuation
    ) async throws {
        let availability = AppleModelAvailabilityReader.current()
        switch availability {
        case .available: break
        case .unsupportedOS: throw OnDeviceGenerationError.unsupportedOS
        case .frameworkAbsent: throw OnDeviceGenerationError.frameworkAbsent
        default: throw OnDeviceGenerationError.unavailable
        }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            try await streamViaFoundationModels(request, into: continuation)
            return
        }
        #endif
        throw OnDeviceGenerationError.unsupportedOS
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private static func streamViaFoundationModels(
        _ request: GenerationRequest,
        into continuation: AsyncThrowingStream<StreamChunk, any Error>.Continuation
    ) async throws {
        let session = LanguageModelSession(instructions: request.systemText)
        let started = ContinuousClock.now
        var emitted = ""

        for try await snapshot in session.streamResponse(to: request.conversationText) {
            if Task.isCancelled { break }
            let full = snapshot.content
            guard full.count > emitted.count else { continue }
            let delta = String(full.suffix(full.count - emitted.count))
            emitted = full
            continuation.yield(.content(delta))
        }

        // tokensGenerated stays 0 because the framework reports no token count here. The UI reads 0
        // as "not reported" rather than drawing a rate that was never measured.
        continuation.yield(.metrics(GenerationMetrics(
            tokensGenerated: 0,
            elapsedSeconds: Double(started.duration(to: .now).seconds),
            finishReason: Task.isCancelled ? .cancelled : .stop
        )))
    }
    #endif
}

private extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
