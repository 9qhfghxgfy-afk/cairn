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

    /// What tracks what is resident in this process, or `nil` when nothing is tracking it.
    ///
    /// Deliberately not `private`: the residency half of this provider lives in
    /// `FoundationModelsProvider+Residency.swift`, and `private` in Swift means file-scoped. It stays
    /// module-internal, so nothing outside `CairnInferenceLocal` can reach it.
    let residency: OnDeviceModelRegistry?

    /// - Parameter residency: the on-device registry to make room through. The Apple model is installed
    ///   and evicted by iOS, so this provider cannot unload it — what it *can* do is release the MLX
    ///   container that shares this process with it, which is the only memory this app owns at that
    ///   moment. Left `nil`, nothing is released and the two runtimes may be resident together.
    public init(residency: OnDeviceModelRegistry? = nil) {
        self.residency = residency
    }

    public var id: String { Self.engineID }
    public var displayName: String { "On-Device (Apple)" }
    public var networkClass: NetworkClass { .onDevice }
    public var serverProfileID: UUID? { nil }
    public var samplingSupport: SamplingSupport { .none }

    /// A model that really runs on this phone, rather than a stub that answers in one's place. This is
    /// what lets the chat's "On device" mode route here: the mock is `.onDevice` too, and honestly so,
    /// because it sends nothing anywhere — but it runs nothing either.
    public var engineKind: EngineKind { .localModel }

    /// Roughly 4,096 tokens of instructions, history and answer together.
    ///
    /// Declared, not measured: the framework offers no way to ask, and a prompt one exchange too long
    /// does not degrade — the whole turn fails, with an error that names neither the prompt nor the
    /// fix. Saying the ceiling out loud is what lets a turn be fitted before it is sent, which is the
    /// difference between "shortened to fit" and a red line in the composer.
    public static let tokenCeiling = 4096
    public var contextTokenCeiling: Int? { Self.tokenCeiling }

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
                    // Room first, then the session. Apple's model is not ours to unload, so the only
                    // memory this app can offer it is the memory its own runtime vacates — and asking
                    // after the session has opened is asking too late.
                    await self.beginResidencyTurn()
                    try await Self.generate(request, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                // Outside the `do`, so a cancelled or failed turn gives the marker back too: a resident
                // entry nobody releases is a resident entry the memory gate keeps paying for.
                await self.endResidencyTurn()
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    private static func generate(
        _ request: GenerationRequest,
        into continuation: AsyncThrowingStream<StreamChunk, any Error>.Continuation
    ) async throws {
        // The reason is carried through rather than flattened into "not available": "turn on Apple
        // Intelligence in Settings" and "this iPhone is not eligible" are different answers with
        // different fixes, and a person told neither goes toggling settings at random.
        let availability = AppleModelAvailabilityReader.current()
        guard availability.isUsable else { throw availability.generationError }
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
        // The tool block is re-rendered from the request's own definitions, so taking it out is a
        // subtraction of the exact text the session appended — not a guess at how it was worded.
        let fitted = PromptContextFit.fit(
            systemText: request.systemText,
            body: request.conversationText,
            toolBlock: ToolPromptBlock.render(request.tools, format: request.toolProtocol),
            tokenCeiling: tokenCeiling
        )
        // Refused here rather than sent and rejected there. The framework's own overflow message names
        // neither the prompt nor the fix, and a turn that cannot fit at all has an answer Cairn can
        // say out loud: shorten it, or switch the chat to a server with a bigger window.
        guard fitted.fits else { throw OnDeviceGenerationError.inputTooLarge }

        let session = LanguageModelSession(instructions: fitted.instructions)
        let started = ContinuousClock.now
        var emitted = ""

        do {
            for try await snapshot in session.streamResponse(to: fitted.body) {
                if Task.isCancelled { break }
                // A snapshot carries the text generated so far, so only its tail is new. The prefix is
                // checked rather than assumed: slicing by length alone can cut mid-word if the framework
                // ever rewrites what came before. A rewrite cannot be un-sent, so the length tail is
                // still the least-wrong remainder when the prefixes disagree.
                let full = snapshot.content
                let delta: String
                if full.hasPrefix(emitted) {
                    delta = String(full.dropFirst(emitted.count))
                } else if full.count > emitted.count {
                    delta = String(full.suffix(full.count - emitted.count))
                } else { continue }
                guard !delta.isEmpty else { continue }
                emitted = full
                continuation.yield(.content(delta))
            }
        } catch {
            // A stop is not a fault. The partial answer is already in the tree, so a cancelled turn
            // closes with its metrics instead of with a red line in the composer.
            if !Task.isCancelled { throw OnDeviceFailure.describe(error) }
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
