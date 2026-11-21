import Foundation

/// A model cannot be taken out of memory because a turn is running in it.
///
/// The refusal carries the model id and nothing else — no path, no file names, no prompt text. The caller
/// turns it into the sentence the person reads, and the registry's own rule is the reason that sentence is
/// true: weights mapped into a process that is generating cannot be handed back mid-stream.
public struct OnDeviceModelBusy: Error, Equatable {
    public var modelID: String
    public init(modelID: String) { self.modelID = modelID }
}

extension OnDeviceModelRegistry {
    /// Frees everything this process can control.
    ///
    /// Apple's model is system-managed and is never resident here under Cairn's claim, so releasing what is
    /// resident is the whole of what this does: Cairn's own builds go, and the runtime reports the system
    /// model's state on its own terms.
    @discardableResult
    public func releaseAll(reason: String) async -> [String] {
        let released = resident.map(\.modelID)
        for id in released { await unloader(id) }
        resident.removeAll()
        activeModelIDs.removeAll()
        deferredReleaseIDs.removeAll()
        return released
    }

    /// Releases every resident this app owns that is **not** mid-turn, and defers the ones that are.
    ///
    /// Unloading a model in the middle of a stream does not produce a clean unload: the runtime is
    /// still holding buffers for it, and the turn dies with the model under it. So a busy model is
    /// marked for release and the release lands at `markIdle`, one turn later, which is also the
    /// moment the person sees the answer they were waiting for.
    @discardableResult
    public func unloadIdleModels() async -> [String] {
        var released: [String] = []
        for model in resident {
            guard !activeModelIDs.contains(model.modelID) else {
                deferredReleaseIDs.insert(model.modelID)
                continue
            }
            await unloader(model.modelID)
            released.append(model.modelID)
        }
        resident.removeAll { model in !activeModelIDs.contains(model.modelID) }
        return released
    }

    /// Hands back the buffers a runtime is holding and not using. Idempotent by design: warning-level
    /// pressure can arrive twice for the same squeeze, and flushing twice must cost nothing.
    public func flushCaches() async {
        await flusher()
    }

    /// A memory warning is not a suggestion. Everything Cairn owns is released and the caller shows
    /// the reason, rather than letting the next allocation be the one that kills the process.
    public func handleMemoryPressure() async -> [String] {
        await releaseAll(reason: "memory-pressure")
    }

    /// Pressure with its severity respected.
    ///
    /// A **warning** costs buffers and not a model: flush the pool and stay loaded, because reloading
    /// a multi-gigabyte build is a worse outcome than the nudge. **Critical** is the system about to
    /// take the process, so idle residents go now and a busy one goes at the end of its turn. The
    /// blunt `handleMemoryPressure()` above remains the "release everything I own" path a caller uses
    /// when it is about to hand the memory to something else, and is deliberately not this function.
    @discardableResult
    public func handleMemoryPressure(level: MemoryPressureLevel) async -> [String] {
        switch level {
        case .warning:
            await flusher()
            return []
        case .critical:
            return await unloadIdleModels()
        }
    }

    /// Takes one named model out of memory now, or says why it cannot.
    ///
    /// The order is the whole contract: the injected unloader runs **before** the registry forgets the id,
    /// because a registry that only forgets has freed no memory. A model that is not resident at all is not
    /// an error — removing a model that happens to be closed is the ordinary case — and a model with a turn
    /// in flight throws rather than deferring, because a deferred release is a promise about a model that is
    /// about to be deleted from disk.
    ///
    /// - Returns: whether anything was actually unloaded.
    @discardableResult
    public func evict(_ modelID: String) async throws -> Bool {
        guard !activeModelIDs.contains(modelID) else { throw OnDeviceModelBusy(modelID: modelID) }
        let wasResident = resident.contains { $0.modelID == modelID }
        if wasResident { await unloader(modelID) }
        markUnloaded(modelID)
        return wasResident
    }
}
