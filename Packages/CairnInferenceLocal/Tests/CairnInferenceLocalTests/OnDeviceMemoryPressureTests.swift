import CairnChatDomain
import Foundation
import Testing
@testable import CairnInferenceLocal

/// What each level of memory pressure is allowed to do, and what it is not.
///
/// The distinction is the whole point: a warning is answered by handing buffers back, a critical event
/// by releasing a model. Answering a warning with a release spends a multi-gigabyte reload on a nudge;
/// answering a critical event with a flush is how a process gets taken while it was busy giving buffers
/// back. And neither is allowed to unload a model out from under a running stream — that request is
/// recorded and lands when the turn ends, which is also the moment the person has their answer.
struct OnDeviceMemoryPressureTests {
    private func model(_ id: String, footprint: Int64 = 1_000_000_000) -> ResidentModel {
        ResidentModel(
            modelID: id, runtime: .mlx, weightsBytes: footprint,
            footprintBytes: footprint, contextLength: 4096
        )
    }

    private func registry(
        headroomBytes: Int64? = 8_000_000_000,
        releases: ReleaseRecorder? = nil,
        flushes: FlushCounter? = nil
    ) -> OnDeviceModelRegistry {
        OnDeviceModelRegistry(
            memory: FixedMemoryReading(bytes: headroomBytes),
            unloader: { id in releases?.record(id) },
            flusher: { flushes?.add() }
        )
    }

    @Test func aWarningFlushesBuffersAndKeepsEveryResidentLoaded() async {
        let releases = ReleaseRecorder()
        let flushes = FlushCounter()
        let held = registry(releases: releases, flushes: flushes)
        await held.markLoaded(model("mlx-on-device"))

        let released = await held.handleMemoryPressure(level: .warning)
        #expect(released.isEmpty)
        #expect(releases.recorded.isEmpty)
        #expect(flushes.count == 1)
        #expect(await held.residentModels().count == 1)
    }

    @Test func aCriticalEventReleasesIdleResidentsThroughTheUnloader() async {
        let releases = ReleaseRecorder()
        let held = registry(releases: releases)
        await held.markLoaded(model("first"))
        await held.markLoaded(model("second"))

        let released = await held.handleMemoryPressure(level: .critical)
        #expect(released == ["first", "second"])
        #expect(releases.recorded == ["first", "second"])
        #expect(await held.residentModels().isEmpty)
    }

    @Test func aModelMidTurnIsNotTakenFromUnderTheStream() async {
        // The deferral is the point. Unloading a model that is generating does not produce a clean
        // unload — the runtime still holds buffers for it, and the turn dies with it — so the request
        // waits, and `markIdle` is where the release actually lands.
        let releases = ReleaseRecorder()
        let held = registry(releases: releases)
        await held.beginTurn(with: model("busy"))
        #expect(await held.isResident("busy"))

        let released = await held.unloadIdleModels()
        #expect(released.isEmpty)
        #expect(releases.recorded.isEmpty)
        #expect(await held.isResident("busy"))

        await held.markIdle("busy")
        #expect(releases.recorded == ["busy"])
        #expect(await held.residentModels().isEmpty)
    }

    @Test func beginTurnCarriesItsOwnEvictionInsteadOfOnlyReportingOne() async {
        // `requestLoad` is a question, and a question frees nothing. The turn entry point has to execute
        // the eviction it recommends, or the single-resident rule stays an opinion about memory instead
        // of a change to it.
        let releases = ReleaseRecorder()
        let held = registry(releases: releases)
        await held.markLoaded(model("old"))

        let decision = await held.beginTurn(with: model("new"))
        #expect(decision == .evictThenAdmit(evict: ["old"]))
        #expect(releases.recorded == ["old"])
        #expect(await held.residentModels().map(\.modelID) == ["new"])
    }

    @Test func beginTurnRefusesWhenTheReadingSaysThereIsNoRoom() async {
        let releases = ReleaseRecorder()
        let held = registry(headroomBytes: 400_000_000, releases: releases)
        let decision = await held.beginTurn(with: model("too-big", footprint: 1_500_000_000))
        #expect(decision == .refuse(.footprintBeyondHeadroom))
        #expect(releases.recorded.isEmpty)
        #expect(await held.residentModels().isEmpty)
    }

    @Test func theWatchAnswersAWarningFromASourceWithoutUnloadingAnything() async throws {
        let flushes = FlushCounter()
        let releases = ReleaseRecorder()
        let held = registry(releases: releases, flushes: flushes)
        await held.markLoaded(model("mlx-on-device"))
        let source = ScriptedPressureSource()
        let watch = OnDeviceMemoryWatch.start(registry: held, sources: [source])

        await source.emit(.warning)
        try await waitUntil { flushes.count == 1 }
        #expect(releases.recorded.isEmpty)
        #expect(await held.residentModels().count == 1)
        await watch.stop()
        #expect(await source.didStop)
    }

    @Test func theWatchReleasesOnACriticalEventThroughTheSameRegistryPath() async throws {
        let releases = ReleaseRecorder()
        let held = registry(releases: releases)
        await held.markLoaded(model("mlx-on-device"))
        let source = ScriptedPressureSource()
        let watch = OnDeviceMemoryWatch.start(registry: held, sources: [source])

        await source.emit(.critical)
        try await waitUntil { releases.recorded == ["mlx-on-device"] }
        #expect(await held.residentModels().isEmpty)
        await watch.stop()
    }
}
