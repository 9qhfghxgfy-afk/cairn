import Testing
@testable import CairnInferenceLocal

/// The deferral, in both directions: pressure must not take a model out from under a running turn, **and**
/// a release asked for during an older turn must not fire at the end of a newer one.
///
/// The first rule is the one that keeps an answer whole. The second is the one that stops the registry
/// from unloading a model on a request nobody made in this turn — which, on a phone, is a reload paid by
/// the person who never asked for it. Both are decided by the same two lines of state in
/// `OnDeviceModelRegistry`, which is why they are asserted side by side.
struct OnDeviceDeferredReleaseTests {
    private func model(_ id: String) -> ResidentModel {
        ResidentModel(
            modelID: id, runtime: .mlx, weightsBytes: 1_000_000_000,
            footprintBytes: 1_000_000_000, contextLength: 4096
        )
    }

    private func registry(_ releases: ReleaseRecorder) -> OnDeviceModelRegistry {
        OnDeviceModelRegistry(
            memory: FixedMemoryReading(bytes: 8_000_000_000),
            unloader: { id in releases.record(id) }
        )
    }

    /// A **critical** event on a busy model is recorded, not executed: the answer finishes, and the model
    /// goes when the turn does.
    @Test func aCriticalEventUnderARunningTurnDefersAndLandsWhenTheTurnEnds() async {
        let releases = ReleaseRecorder()
        let held = registry(releases)
        await held.beginTurn(with: model("mlx-on-device"))

        let released = await held.handleMemoryPressure(level: .critical)
        #expect(released.isEmpty, "a busy model is not taken mid-stream")
        #expect(releases.recorded.isEmpty)
        #expect(await held.isResident("mlx-on-device"))

        await held.markIdle("mlx-on-device")
        #expect(releases.recorded == ["mlx-on-device"], "the deferred release lands at the end of the turn")
        #expect(await held.residentModels().isEmpty)
    }

    /// The stale-request case. Pressure arrives while turn 1 is running, so the release is deferred; a
    /// second turn then starts in the **same** model, which makes that request about a model that is no
    /// longer idle. Ending turn 2 must therefore release nothing — the release was turn 1's, and turn 1
    /// was never idle.
    @Test func aDeferredReleaseDoesNotSurviveANewTurnInTheSameModel() async {
        let releases = ReleaseRecorder()
        let held = registry(releases)
        await held.beginTurn(with: model("mlx-on-device"))
        _ = await held.handleMemoryPressure(level: .critical)
        #expect(releases.recorded.isEmpty)

        await held.beginTurn(with: model("mlx-on-device"))
        #expect(await held.isResident("mlx-on-device"))

        await held.markIdle("mlx-on-device")
        #expect(releases.recorded.isEmpty, "a request made during the previous turn must not fire at this one's end")
        #expect(await held.isResident("mlx-on-device"))
    }
}
