import Foundation
import Testing
@testable import CairnInferenceLocal

/// Taking one model out of memory by name, which is what a deletion does before it touches a byte.
///
/// The two facts that matter are the order and the refusal: an idle model goes through the injected
/// unloader rather than merely leaving the registry's list, and a model with a turn in flight is never
/// taken at all. A registry that only forgets an id has freed no memory, and one that forgets a busy model
/// tears an answer in half.
struct OnDeviceEvictTests {
    private func candidate(_ id: String, footprint: Int64 = 1) -> ResidentModel {
        ResidentModel(modelID: id, runtime: .mlx, weightsBytes: footprint,
                      footprintBytes: footprint, contextLength: 4096)
    }

    private func registry(_ recorder: ReleaseRecorder) -> OnDeviceModelRegistry {
        OnDeviceModelRegistry(
            memory: FixedMemoryReading(bytes: 8_000_000_000),
            unloader: { id in recorder.record(id) }
        )
    }

    @Test func anIdleResidentGoesThroughTheUnloaderRatherThanTheList() async throws {
        let calls = ReleaseRecorder()
        let held = registry(calls)
        await held.markLoaded(candidate("a"))

        #expect(try await held.evict("a") == true)
        #expect(calls.recorded == ["a"])
        #expect(await held.residentModels().isEmpty)
    }

    @Test func aModelNobodyHeldIsNotAnError() async throws {
        let calls = ReleaseRecorder()
        let held = registry(calls)
        // Deleting a model this phone downloaded and never loaded is the ordinary case, and asking a
        // runtime to release what it never loaded is not a failure worth reporting to a person.
        #expect(try await held.evict("never-loaded") == false)
        #expect(calls.recorded.isEmpty)
    }

    @Test func aTurnInFlightIsRefusedBeforeAnythingIsReleased() async {
        let calls = ReleaseRecorder()
        let held = registry(calls)
        await held.beginTurn(with: candidate("mlx-on-device"))

        await #expect(throws: OnDeviceModelBusy(modelID: "mlx-on-device")) {
            _ = try await held.evict("mlx-on-device")
        }
        #expect(calls.recorded.isEmpty, "the refusal must not have touched the runtime")
        #expect(await held.residentModels().map(\.modelID) == ["mlx-on-device"])
    }

    @Test func theAnswerAboutATurnComesFromTheRegistryRatherThanTheCaller() async {
        let held = registry(ReleaseRecorder())
        #expect(await held.isTurnActive("a") == false)
        await held.beginTurn(with: candidate("a"))
        #expect(await held.isTurnActive("a") == true)
        await held.markIdle("a")
        #expect(await held.isTurnActive("a") == false)
    }

    @Test func evictingAfterTheTurnEndsReleasesTheModelExactlyOnce() async throws {
        let calls = ReleaseRecorder()
        let held = registry(calls)
        await held.beginTurn(with: candidate("a"))
        await held.markIdle("a")

        #expect(try await held.evict("a") == true)
        #expect(calls.recorded == ["a"])
        // A second call is a no-op, not a second release of a model the runtime already gave back.
        #expect(try await held.evict("a") == false)
        #expect(calls.recorded == ["a"])
    }

    /// What this proves is the hand-off, not a promise inside `evict`: pressure that arrived mid-turn is
    /// carried out at `markIdle`, the model leaves the registry with its deferred entry behind it, and a
    /// later load plus evict of the same id releases exactly once more rather than inheriting the old
    /// request. A stale deferred entry surviving an unload is what would make a later idle period release
    /// a model nobody had asked about.
    @Test func aReleaseDeferredByPressureDoesNotSurviveTheModelItWasAskedFor() async throws {
        let calls = ReleaseRecorder()
        let held = registry(calls)
        await held.beginTurn(with: candidate("a"))
        // Pressure arrives while the turn is running: the request is deferred, not carried out.
        _ = await held.unloadIdleModels()
        await held.markIdle("a")
        #expect(calls.recorded == ["a"], "the deferred release lands when the turn ends")

        // The same id is loaded again — a different model in the runtime's eyes — and evicted on its own
        // account. Two releases, one per residency, and no third from the entry pressure left behind.
        await held.markLoaded(candidate("a"))
        #expect(try await held.evict("a") == true)
        #expect(calls.recorded == ["a", "a"])
        await held.markIdle("a")
        #expect(calls.recorded == ["a", "a"])
    }
}
