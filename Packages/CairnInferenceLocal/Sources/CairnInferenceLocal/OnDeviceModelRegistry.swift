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
    private let unloader: @Sendable (String) async -> Void
    private var resident: [ResidentModel] = []

    public init(
        memory: any MemoryReading = SystemMemoryReading(),
        unloader: @escaping @Sendable (String) async -> Void = { _ in }
    ) {
        self.memory = memory
        self.unloader = unloader
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
    }

    /// Frees everything this process can control. Apple's own model is system-managed, so it is
    /// reported as unloaded from Cairn's side only.
    @discardableResult
    public func releaseAll(reason: String) async -> [String] {
        let released = resident.map(\.modelID)
        for id in released { await unloader(id) }
        resident.removeAll()
        return released
    }

    /// A memory warning is not a suggestion. Everything Cairn owns is released and the caller shows
    /// the reason, rather than letting the next allocation be the one that kills the process.
    public func handleMemoryPressure() async -> [String] {
        await releaseAll(reason: "memory-pressure")
    }
}
