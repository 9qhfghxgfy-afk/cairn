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
///
/// Memory has a lifecycle here, and it is the reason a jetsam report existed to be fixed. Every turn
/// asks an injected gate for permission before it allocates (`NativeMemoryAdmitting`), runs inside a
/// `MLXTurnLedger` turn so a release asked for mid-stream lands at the end instead of under the stream,
/// and takes its container from one pooled `MLXContainerPool` instead of loading a fresh one. The gate
/// is injected rather than hard-coded because the numbers it needs — the model's size on disk, the
/// process's headroom — belong to the layer that owns the model store, and because a gate that cannot
/// be substituted is a gate that cannot be tested.
public actor MLXNativeProvider: InferenceProvider {
    public static let engineID = "on-device.mlx"
    public static let modelID = "mlx-on-device"

    /// Read on demand rather than frozen at launch: a model that finishes downloading while Cairn is
    /// open should be loadable on the next turn, not at the next launch. `nonisolated` because the
    /// registry reads availability from any thread, and a `@Sendable` closure is safe to call there.
    ///
    /// It is a **list**, not a single folder, because a phone can hold several downloaded models and the
    /// chat has to be able to name them. Before this, the engine reported one synthetic model whatever was
    /// on disk, so a person with three folders on an iPhone saw one entry in the picker and no way to
    /// pick. Internal rather than private because the listing and switching half of this type lives in
    /// `MLXNativeProvider+Models.swift`.
    let installed: @Sendable () -> [NativeInstalledModel]
    private let admission: any NativeMemoryAdmitting
    /// Internal, not private: the switching path releases through the pool and the ledger, and a
    /// `private` member is unreachable from the extension in `MLXNativeProvider+Models.swift`. The pool is
    /// read there for one question only — whether any container is still held, which is what decides
    /// whether the residency claim may be cleared.
    let pool: MLXContainerPool
    let ledger: MLXTurnLedger
    /// Internal, not private: the switching path in `MLXNativeProvider+Models.swift` has to clear the
    /// residency claim when it hands a model's weights back, and a `private` member is unreachable from
    /// an extension in another file.
    var loaded: String?
    /// The folder this engine is pointed at, set at wiring time and moved by `selectModel`. Per-engine
    /// rather than per-turn because loading weights is not free: which model is live is the engine's
    /// state, and the picker has to move that state rather than only repaint a label.
    var activeModelID: String?

    /// - Parameter modelDirectory: a folder of already-installed, already-verified weights.
    ///   Cairn's own downloader owns that folder; this engine never fetches anything.
    public init(modelDirectory: URL? = nil) {
        self.init(directoryResolver: { modelDirectory })
    }

    /// - Parameter directoryResolver: the same folder, looked up every time it is needed. The App layer
    ///   points this at the model store, so installing a model makes this engine usable without a
    ///   relaunch and without re-registering the provider.
    public init(directoryResolver: @escaping @Sendable () -> URL?) {
        self.init(directoryResolver: directoryResolver, admission: NativeAdmissionUnwired())
    }

    /// The shape with more than one folder on the phone.
    ///
    /// - Parameters:
    ///   - installed: the folders this phone holds, newest first, each one loadable by this runtime. The
    ///     App layer reads them; this engine never does.
    ///   - activeModelID: the folder the person last chose, read back from the saved selection. When it
    ///     no longer describes a folder on disk, the newest installed one is used instead — the same rule
    ///     a turn follows, so the listing and the turn cannot disagree about what is live.
    public init(
        installed: @escaping @Sendable () -> [NativeInstalledModel],
        activeModelID: String? = nil,
        admission: any NativeMemoryAdmitting = NativeAdmissionUnwired()
    ) {
        self.init(
            installed: installed,
            activeModelID: activeModelID,
            admission: admission,
            pool: MLXContainerPool()
        )
    }

    /// The full form: folders, the chosen one, **and** the memory gate that decides whether a turn may
    /// allocate.
    ///
    /// - Parameter admission: the measured gate. Left at `NativeAdmissionUnwired`, turns are allowed
    ///   with a zero buffer pool, which is a small and honest posture but not a measured one — so the
    ///   app always passes a gate that reads `os_proc_available_memory()` and the model's size on disk.
    public init(
        directoryResolver: @escaping @Sendable () -> URL?,
        admission: any NativeMemoryAdmitting
    ) {
        self.init(
            installed: {
                guard let directory = directoryResolver() else { return [] }
                return [NativeInstalledModel.unwired(directory: directory)]
            },
            activeModelID: nil,
            admission: admission
        )
    }

    /// The single path every initialiser ends in, so a pool and a ledger are built exactly one way:
    /// the ledger's release has to point at the same pool the turns load from, or a release that reports
    /// success could be releasing nothing.
    private init(
        installed: @escaping @Sendable () -> [NativeInstalledModel],
        activeModelID: String?,
        admission: any NativeMemoryAdmitting,
        pool: MLXContainerPool
    ) {
        self.installed = installed
        self.activeModelID = activeModelID
        self.admission = admission
        self.pool = pool
        self.ledger = MLXTurnLedger(
            onFlush: { MLXRuntimeMemory.flushBufferCache() },
            onRelease: { [pool] in await pool.releaseNow() }
        )
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
        // "A model is installed" means "a folder this runtime can load is installed", which is what the
        // App layer hands over — a GGUF folder on disk is real but not loadable here, and it is counted on
        // the Servers row rather than making this engine claim it can run it.
        NativeRuntimeAvailability.current(hasInstalledModel: !installed().isEmpty)
    }

    /// The models on this phone this runtime can load, newest first — see
    /// `MLXNativeProvider+Models.swift`, which also holds the switching rule.
    public func models() async throws -> [ModelInfo] {
        installedRecords()
    }

    /// Resident model, for the Running tab. `nil` until a turn has really started answering, and cleared
    /// as soon as the pool really is empty — claiming a model is in memory when nothing is holding it
    /// would be a number the user then trusts.
    public func residentModelId() -> String? { loaded }

    public nonisolated func stream(
        _ request: GenerationRequest
    ) -> AsyncThrowingStream<StreamChunk, any Error> {
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
                    // Resolved inside the actor, because which folder is live is actor state and the
                    // person may have switched models between two turns. A name the engine does not have
                    // is `modelNotInstalled`, not a load attempt against somebody else's weights.
                    guard let directory = await self.turnDirectory(for: request) else {
                        throw NativeGenerationError.modelNotInstalled
                    }
                    let cacheLimitBytes = try await self.admitAndBeginTurn(directory: directory)
                    do {
                        try await self.run(
                            request, directory: directory, cacheLimitBytes: cacheLimitBytes
                        ) { chunk in
                            bridge.receive(chunk)
                        }
                    } catch {
                        // The turn closes before the error surfaces. A refused or broken generation
                        // still owes its bookkeeping, and a stream that ends while the ledger still
                        // counts it is how a release gets skipped for good.
                        await self.endTurn(directory: directory)
                        throw error
                    }
                    // Ahead of `complete()`, so a consumer that starts its next turn at once sees this
                    // one closed and cannot overlap two turns inside the ledger.
                    await self.endTurn(directory: directory)
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

    /// Permission to allocate, and the ledger turn that goes with it.
    ///
    /// Asked at load time, never cached: a headroom reading describes the moment it was taken, and a
    /// model that fitted at launch may not fit after a photo has been decoded into this process.
    private func admitAndBeginTurn(directory: URL) async throws -> Int {
        let verdict = await admission.admitLoading(modelDirectory: directory)
        switch verdict {
        case .refuse(let reason):
            throw NativeGenerationError.insufficientMemory(reason: reason)
        case .admit(let cacheLimitBytes):
            await ledger.beginTurn()
            return cacheLimitBytes
        }
    }

    /// The engine call, made from inside the actor so the pool never crosses the actor boundary.
    private func run(
        _ request: GenerationRequest,
        directory: URL,
        cacheLimitBytes: Int,
        emit: @escaping @Sendable (StreamChunk) -> Void
    ) async throws {
        try await MLXNativeEngine.stream(
            request: request,
            modelDirectory: directory,
            cacheLimitBytes: cacheLimitBytes,
            pool: pool,
            emit: emit
        )
    }

    /// Closes the ledger turn — which hands the runtime's buffer pool back, or completes a release
    /// pressure asked for while this turn was running — and tells the gate the model is idle again.
    private func endTurn(directory: URL) async {
        await ledger.endTurn()
        await admission.turnFinished(modelDirectory: directory)
        let holding = await pool.isLoaded
        if !holding { loaded = nil }
    }

    /// Hands the weights back if nothing is generating.
    ///
    /// This is what backgrounding calls. A release asked for under a running turn is recorded and lands
    /// at that turn's `endTurn`: taking a model out from under a stream produces a torn answer and frees
    /// nothing the runtime was not already going to free — while backgrounding is precisely the moment
    /// iOS is deciding whether to take the process, so the request is never dropped, only sequenced.
    public func unloadIfIdle() async {
        await ledger.requestRelease()
        let holding = await pool.isLoaded
        if !holding { loaded = nil }
    }

    /// Warning-level pressure: buffers back, model stays. Reloading a gigabyte-scale build costs more
    /// than the nudge ever will, and the next turn is faster for it.
    public func flushCachesIfIdle() async {
        await ledger.requestFlush()
    }

    private func markResident() { loaded = Self.modelID }
}
