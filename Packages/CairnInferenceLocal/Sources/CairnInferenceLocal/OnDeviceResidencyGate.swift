import Foundation
import CairnChatDomain

/// The real answer to the memory question a hybrid turn asks, replacing the domain's
/// `NeverTwoOnDeviceResident` default once the app wires one.
///
/// The seam exists because `os_proc_available_memory()` lives above `CairnChatDomain`; this type
/// sits on the near side of it, so the domain never imports a runtime and the app layer still owns
/// the injection (`App/HybridWiring.swift` builds this and hands it to every session).
///
/// Two rules, both absolute:
/// - an answer of "two may be resident" requires a **fresh, positive** reading that fits both
///   footprints inside the usable share. Unknown or tight readings answer no, because overflowing
///   the ceiling costs the whole conversation rather than one candidate;
/// - `evictResidentModel()` really releases. It goes through `OnDeviceModelRegistry`, which calls
///   the injected unloader for every model this process owns, so "sequentially, with a clean
///   release between them" is an event and not a gap in timing.
public struct OnDeviceResidencyGate: HybridResidencyGating {
    private let registry: OnDeviceModelRegistry
    private let memory: any MemoryReading
    private let modelFootprintBytes: Int64

    public init(
        registry: OnDeviceModelRegistry,
        memory: any MemoryReading = SystemMemoryReading(),
        modelFootprintBytes: Int64 = TwoResidentBudget.conservativeModelFootprintBytes
    ) {
        self.registry = registry
        self.memory = memory
        self.modelFootprintBytes = modelFootprintBytes
    }

    /// Re-read on every call: the reading describes the moment it was taken, not the session, so
    /// caching one would be caching a promise the device may already have withdrawn.
    public func allowsTwoOnDeviceModelsResident() -> Bool {
        TwoResidentBudget.allowsTwoResident(
            headroomBytes: memory.availableMemoryBytes(),
            modelFootprintBytes: modelFootprintBytes
        )
    }

    /// Typed reason only — the registry returns the ids it released, and no model content is
    /// carried out of here.
    @MainActor
    public func evictResidentModel() async {
        _ = await registry.releaseAll(reason: "hybrid-sequential-release")
    }
}
