import Foundation

/// Who is holding which on-device model, and what has to be unloaded to make room.
///
/// The hard rule lives here: at most one on-device model resident unless a fresh headroom reading
/// says two fit with the app's own reserve intact. Headroom is re-read on every decision, because
/// `os_proc_available_memory()` describes the moment the question was asked, not the session.
///
/// Eviction is reported and executed through an injected unloader so this type stays testable with
/// no runtime loaded — and so a memory warning cannot be ignored on the way to being killed.
public actor OnDeviceModelRegistry {
    private let memory: any MemoryReading
    let unloader: @Sendable (String) async -> Void
    let flusher: @Sendable () async -> Void
    var resident: [ResidentModel] = []
    /// Residents with a turn running in them right now. Pressure may not take one of these away
    /// mid-stream — `unloadIdleModels` defers that release to the end of the turn instead.
    var activeModelIDs: Set<String> = []
    /// A release pressure asked for and could not take yet, applied the moment the turn ends.
    var deferredReleaseIDs: Set<String> = []

    /// - Parameters:
    ///   - memory: the headroom source. Defaults to the real process reading; a test injects a fixed
    ///     or moved reading so a refusal is proven against a number rather than the machine running
    ///     the test.
    ///   - unloader: what it actually takes to release a model, given its id. It defaults to doing
    ///     nothing — the registry can be used before any runtime is attached — but an app that owns a
    ///     runtime passes the real release here, because a registry that only forgets an id has freed
    ///     no memory and would make every answer below a lie.
    ///   - flusher: what it takes to hand back the buffers a runtime is holding and not using — the
    ///     Metal buffer pool of a local runtime, which is dirty memory this process owns. Warning-level
    ///     pressure calls this instead of unloading, because a model still resident after a flush is a
    ///     next turn that does not have to reload from disk.
    public init(
        memory: any MemoryReading = SystemMemoryReading(),
        unloader: @escaping @Sendable (String) async -> Void = { _ in },
        flusher: @escaping @Sendable () async -> Void = {}
    ) {
        self.memory = memory
        self.unloader = unloader
        self.flusher = flusher
    }

    public func residentModels() -> [ResidentModel] { resident }

    public func isResident(_ modelID: String) -> Bool {
        resident.contains { $0.modelID == modelID }
    }

    public func requestLoad(
        _ candidate: ResidentModel,
        allowSecondResident: Bool = false
    ) -> ResidentDecision {
        ResidentModelPolicy.decide(
            current: resident,
            candidate: candidate,
            headroomBytes: memory.availableMemoryBytes(),
            allowSecondResident: allowSecondResident
        )
    }

    /// Applies a decision the caller has carried out: the named models really were released.
    public func markLoaded(_ model: ResidentModel, evicting evicted: [String] = []) {
        resident.removeAll { evicted.contains($0.modelID) || $0.modelID == model.modelID }
        resident.append(model)
    }

    public func markUnloaded(_ modelID: String) {
        resident.removeAll { $0.modelID == modelID }
        activeModelIDs.remove(modelID)
        deferredReleaseIDs.remove(modelID)
    }

    /// The one call an engine makes before it loads anything: ask whether this model may be resident,
    /// and **carry the answer out** rather than reporting it.
    ///
    /// `requestLoad` is a question and a question frees nothing. This applies the decision — evicting
    /// through the injected unloader, then recording the candidate — so a caller cannot read "evict
    /// first, then admit" and forget to evict. The candidate is marked active at the same moment,
    /// because from here on a turn is running in it.
    @discardableResult
    public func beginTurn(
        with candidate: ResidentModel,
        allowSecondResident: Bool = false
    ) async -> ResidentDecision {
        let decision = requestLoad(candidate, allowSecondResident: allowSecondResident)
        switch decision {
        case .refuse:
            break
        case .admit:
            markLoaded(candidate)
            markTurnStarted(candidate.modelID)
        case .evictThenAdmit(let evicted):
            for id in evicted where id != candidate.modelID { await unloader(id) }
            markLoaded(candidate, evicting: evicted)
            markTurnStarted(candidate.modelID)
        }
        return decision
    }

    /// A turn has started in this model. While it is active, pressure defers rather than kills it.
    public func markActive(_ modelID: String) {
        markTurnStarted(modelID)
    }

    /// Whether a turn is running in this model right now.
    ///
    /// This is the question a removal asks before it touches a byte: weights mapped into a process that is
    /// generating cannot be taken away, and the answer has to come from the thing that owns the claim
    /// rather than from the caller's memory of what it started.
    public func isTurnActive(_ modelID: String) -> Bool {
        activeModelIDs.contains(modelID)
    }

    /// Records that a turn is running in this model, and drops any release pressure left over from the
    /// idle period before it.
    ///
    /// Both halves belong together. A deferred release is a request about the model **as it was when the
    /// pressure arrived** — idle, and safe to take. Carrying that request into a new turn in the same
    /// model would take a model that is not idle, at the moment its answer finishes, which is the exact
    /// failure the deferral exists to avoid. And `markIdle` acts only when a deferred entry exists, so a
    /// stale entry would also make the next idle period unload a model nobody had asked to unload.
    private func markTurnStarted(_ modelID: String) {
        activeModelIDs.insert(modelID)
        deferredReleaseIDs.remove(modelID)
    }

    /// The turn ended. If pressure asked for this model back while it was busy, that request is
    /// honoured here — which is the whole point of deferring it rather than dropping the stream.
    public func markIdle(_ modelID: String) async {
        activeModelIDs.remove(modelID)
        guard deferredReleaseIDs.remove(modelID) != nil else { return }
        if resident.contains(where: { $0.modelID == modelID }) {
            await unloader(modelID)
            markUnloaded(modelID)
        }
    }
}
