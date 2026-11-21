import CairnChatDomain
import Foundation

#if !targetEnvironment(simulator) && canImport(MLXLLM) && canImport(MLXLMCommon)
import MLXLLM
import MLXLMCommon
#endif

/// The only place in Cairn that touches MLX.
///
/// Everything above this type is Swift 6 strict; this file is Swift 5, and the boundary the app sees is
/// the actor in `MLXNativeProvider`. Weight loading and generation happen on a real device only: Metal is
/// not present on the simulator, so the real block is compiled out there rather than attempted and failed
/// at runtime — and the same is true of a build that left the runtime out.
///
/// What these call shapes were written against, and what is still owed:
///
/// - Verified against the package's own `2.31.3` sources, file by file, on 2026-11-19:
///   `loadModelContainer(hub:directory:progressHandler:)` (`ModelFactory.swift`); `ModelContainer`'s
///   `prepare(input:)` and `generate(input:parameters:wiredMemoryTicket:) -> AsyncStream<Generation>`
///   (`ModelContainer.swift`); `Generation`'s `.chunk`/`.info`/`.toolCall` and the fields of
///   `GenerateParameters` and `GenerateCompletionInfo` (`Evaluate.swift`); `UserInput(chat:processing:tools:)`
///   (`UserInput.swift`); `Chat.Message.system/user/assistant/tool` (`Chat.swift`); and `ToolCall`'s
///   `function.name`/`function.arguments` (`Tool/ToolCall.swift`). The envelope built in `MLXToolSpecs` is
///   the same dictionary that package builds for itself and the same one its own `ChatSessionTests` uses.
/// - Not verified from this machine: that it *compiles*. The dependency is linked only under `CAIRN_MLX=1`
///   (see `Package.swift`), so no compiler here has seen these symbols. The shapes are as certain as
///   reading the tag makes them; the build is owed to a device build with the runtime linked, and
///   ROADMAP.md carries that debt rather than this comment hiding it.
/// - Not verified anywhere yet: that a given model honours the sampling values it is handed, that its
///   chat template renders the tool block, or how fast it runs. Those are device observations.
///
/// The pin is `2.31.3` rather than the `3.x` line because 2.31.3 is the release whose
/// `ModelContainer`/`Generation` surface this file uses; the 3.x line declares a newer tools-version and
/// adds macro plugins, which is more to compile for no change to the calls made here. Both lines declare
/// the same iOS floor, so the choice is about the API this file can vouch for and the cost of the build.
#if !targetEnvironment(simulator) && canImport(MLXLLM) && canImport(MLXLMCommon)
enum MLXNativeEngine {
    static let isCompiledIn = true

    /// Streams one turn from weights already on the device, in Cairn's chunk vocabulary.
    ///
    /// Nothing is fetched. The folder is the one Cairn's own downloader filled and verified, so this
    /// engine either loads it or says it is not there — a second downloader here would be a second path
    /// by which a model could arrive on the phone without the user having chosen it.
    ///
    /// The container comes from `MLXContainerPool` rather than being loaded here. Loading per turn was
    /// the old shape, and it is what a jetsam report reads as dirty memory: every load allocates, the
    /// runtime parks the old buffers in its pool instead of returning them, and nothing ever called
    /// `clearCache()`. One pooled container plus a cache limit applied before the cold load is the fix;
    /// `cacheLimitBytes` arrives from the memory gate that measured the phone, not from a constant here.
    ///
    /// Tools travel as schemas only. No handler is handed to the runtime, because a tool that ran inside
    /// the runtime would have bypassed the chat's `Tools` chip, the per-tool toggle and the outbound
    /// acknowledgement; a call therefore comes back as a `.toolCall` chunk for `ToolLoop` to run.
    static func stream(
        request: GenerationRequest,
        modelDirectory: URL,
        cacheLimitBytes: Int,
        pool: MLXContainerPool,
        emit: @escaping @Sendable (StreamChunk) -> Void
    ) async throws {
        let marker = modelDirectory.appendingPathComponent("config.json").path
        guard FileManager.default.fileExists(atPath: marker) else {
            throw NativeGenerationError.modelNotInstalled
        }
        let turns = MLXChatTranscript.turns(for: request)
        guard !turns.isEmpty else { throw NativeGenerationError.nothingToAnswer }

        // Reused across turns, and the load inside it is already inside the cache budget.
        let container = try await pool.container(
            for: modelDirectory, cacheLimitBytes: cacheLimitBytes
        )

        var chat: [Chat.Message] = []
        for turn in turns {
            switch turn.role {
            case .system: chat.append(Chat.Message.system(turn.text))
            case .user: chat.append(Chat.Message.user(turn.text))
            case .assistant: chat.append(Chat.Message.assistant(turn.text))
            case .tool: chat.append(Chat.Message.tool(turn.text))
            }
        }
        let schemas = MLXToolSpecs.schemas(for: request.tools)
        let input = schemas.isEmpty
            ? UserInput(chat: chat)
            : UserInput(chat: chat, tools: schemas)

        let started = ContinuousClock.now
        var measured: GenerateCompletionInfo?
        var callCount = 0
        do {
            let prepared = try await container.prepare(input: input)
            let events = try await container.generate(
                input: prepared, parameters: parameters(for: request)
            )
            for await event in events {
                if Task.isCancelled { break }
                switch event {
                case .chunk(let text):
                    if !text.isEmpty { emit(.content(text)) }
                case .info(let info):
                    measured = info
                case .toolCall(let call):
                    callCount += 1
                    if let mapped = MLXToolCalls.request(call, id: "mlx-call-\(callCount)") {
                        emit(.toolCall(mapped))
                    }
                }
            }
        } catch is CancellationError {
            // A stop is not a fault: what was produced already went out, so the turn closes with its
            // metrics rather than with a red line in the composer.
        } catch let issue as NativeGenerationError {
            throw issue
        } catch {
            throw NativeGenerationError.generationFailed
        }

        emit(.metrics(GenerationMetrics(
            tokensGenerated: measured?.generationTokenCount ?? 0,
            promptTokens: measured?.promptTokenCount,
            elapsedSeconds: started.duration(to: .now).seconds,
            finishReason: finishReason(info: measured, cancelled: Task.isCancelled)
        )))
    }
}
#else
/// The shape this file must keep so the provider compiles identically on the simulator and in a build
/// that left the runtime out: the answer is always "not here", and it is always typed. The signature
/// matches the real engine exactly — cache limit and pool included — so the provider's memory path is
/// the same code in both shapes and cannot drift between them.
enum MLXNativeEngine {
    static let isCompiledIn = false

    static func stream(
        request: GenerationRequest,
        modelDirectory: URL,
        cacheLimitBytes: Int,
        pool: MLXContainerPool,
        emit: @escaping @Sendable (StreamChunk) -> Void
    ) async throws {
        if NativeRuntimeBuild.isSimulatorBuild {
            throw NativeGenerationError.runtimeUnavailableOnSimulator
        }
        throw NativeGenerationError.runtimeExcludedFromThisBuild
    }
}
#endif

private extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
