import Foundation
import CairnChatDomain
import CairnInferenceLocal

/// The residency half of the app's wiring: the memory answer a hybrid turn asks, built from what
/// this device actually reports rather than from a rule the code would like to believe.
///
/// `CairnChatDomain` cannot import `CairnInferenceLocal` — the memory reading sits above it, and
/// importing it back would close a cycle — so the domain declares the seam (`HybridResidencyGating`)
/// and answers no by default. This file is where the real answer is built and handed down.
///
/// Honesty about what is measured:
/// - the headroom reading is `os_proc_available_memory()`, which has no macOS equivalent. A host
///   build therefore reads `nil`, which the gate treats as unknown and answers no. There is no
///   invented ceiling;
/// - the release is real but bounded: `OnDeviceModelRegistry.releaseAll` calls the injected unloader
///   for every model this process owns. Apple's own model is system-managed and MLX does not yet
///   expose a per-model unload, so a runtime-level unload is only as strong as the unloader the
///   runtime registers with the registry.
enum HybridWiring {
    /// The gate every session in the workspace gets, reading fresh headroom on each question and
    /// releasing through the same registry the memory-pressure watch uses.
    static func residencyGate(_ registry: OnDeviceModelRegistry) -> any HybridResidencyGating {
        OnDeviceResidencyGate(registry: registry, memory: SystemMemoryReading())
    }

    /// Two on-device candidates may share an instant only on a positive, measured reading. Exposed
    /// so the Servers screen can say which rule it is applying instead of implying one.
    static func allowsTwoOnDeviceModelsResident(
        memory: any MemoryReading = SystemMemoryReading()
    ) -> Bool {
        TwoResidentBudget.allowsTwoResident(headroomBytes: memory.availableMemoryBytes())
    }
}
