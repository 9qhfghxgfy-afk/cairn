import Foundation

/// The on-device memory question a hybrid turn has to ask, and cannot answer by itself.
///
/// The rule is absolute: never hold two on-device models resident in the same process. What
/// counts as an exception is a measurement — `os_proc_available_memory()` against the resident
/// footprint policy — and that lives in `CairnInferenceLocal`, which sits **above** this module.
/// Importing it from here would close a cycle, so the answer arrives through this seam and the
/// app layer injects it.
///
/// The default answers no. An unknown headroom reading is not an unlimited one, and overflowing
/// the ceiling costs the whole conversation rather than one candidate.
public protocol HybridResidencyGating: Sendable {
    /// True only when a fresh reading shows room for a second on-device model alongside the
    /// first. Must be cheap and safe to call off the main actor.
    func allowsTwoOnDeviceModelsResident() -> Bool

    /// Release whatever is resident before the next on-device run starts. Called between
    /// sequential on-device candidates, so "sequentially with a clean release" is real rather
    /// than two loads that happen to miss each other in time.
    @MainActor func evictResidentModel() async
}

/// The default gate, and the one every test and every unwired session gets: one on-device model
/// at a time, always released before the next one runs.
public struct NeverTwoOnDeviceResident: HybridResidencyGating {
    public init() {}

    public func allowsTwoOnDeviceModelsResident() -> Bool { false }

    @MainActor public func evictResidentModel() async {}
}