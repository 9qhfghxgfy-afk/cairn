import CairnChatDomain
import Foundation

/// The residency half of the Apple-model provider, kept out of the streaming file so both halves read
/// cleanly.
///
/// Apple's system model is not Cairn's to unload. Nothing in this module can ask iOS to put it back,
/// and pretending otherwise would be a claim about someone else's memory. What Cairn *can* do, and
/// what this file does, is release what it owns before the system model runs: the MLX container and its
/// buffer pool, which are several gigabytes of dirty memory sitting in the same process the system
/// model is about to be added to. Two on-device runtimes resident at once is the configuration a
/// jetsam kill is most likely to arrive from, and this is the one place both are in play.
extension FoundationModelsProvider {
    /// Makes room for the system model, but only if the system model is really going to run.
    ///
    /// Availability is read here rather than assumed from an earlier turn: on a phone where the model is
    /// unavailable, releasing the MLX container would cost a working engine and buy nothing.
    func beginResidencyTurn() async {
        guard let residency else { return }
        guard AppleModelAvailabilityReader.current().isUsable else { return }
        // Everything Cairn owns goes, not only MLX. `releaseAll` is the honest verb: it goes through the
        // injected unloader, and an id this app cannot release is reported as unloaded from Cairn's side
        // only — which is exactly the case for Apple's own model.
        _ = await residency.releaseAll(reason: "apple-model-about-to-run")
        await residency.markLoaded(Self.residencyMarker)
    }

    /// The turn is over, so Cairn stops claiming the system model as its own resident.
    ///
    /// It was never Cairn's to hold: leaving the marker in place would have the memory gate price a
    /// model it cannot measure and cannot release into every later decision about loading MLX.
    func endResidencyTurn() async {
        guard let residency else { return }
        await residency.markUnloaded(Self.modelID)
    }

    /// The entry this provider records while the system model is running.
    ///
    /// The framework publishes no footprint for its model, so `weightsBytes` is honestly zero and
    /// `footprintBytes` carries the app's own conservative per-model figure — the same number
    /// `TwoResidentBudget` prices an unknown model at. That is a stand-in, not a measurement, and it is
    /// here so the registry's arithmetic does not read "zero bytes" as "this one is free".
    ///
    /// `static let` and not `static var`: the value is built only from this type's own static constants,
    /// so it is a constant rather than a knob, and a mutable global of a `Sendable` struct is the one
    /// shape Swift 6's global-strict-concurrency rule exists to reject.
    static let residencyMarker: ResidentModel = ResidentModel(
        modelID: modelID,
        runtime: .appleFoundationModels,
        weightsBytes: 0,
        footprintBytes: TwoResidentBudget.conservativeModelFootprintBytes,
        contextLength: tokenCeiling
    )
}
