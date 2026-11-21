import XCTest
import SwiftUI
import CairnChatDomain
import CairnInferenceLocal
import CairnInferenceNative

/// Who is allowed to take an on-device model out of memory, and what the answer really means.
///
/// The registry decides and the sink executes, and the honest part is the difference between the two: a
/// release of Apple's model is a report, not a freeing, and a release of MLX while a generation is
/// running is a request rather than an event. Both answers are asserted here because both are the kind
/// that, if they are wrong, make every later memory decision read more confident than the device is.
@MainActor
final class OnDeviceReleaseWiringTests: XCTestCase {
    /// Apple's model is installed and evicted by iOS. A sink that reported it as released would leave
    /// every later decision priced from a freeing that never happened.
    func testReleasingApplesModelIsAnsweredAsNothingFreed() async {
        let sink = OnDeviceUnloadSink()
        await sink.attach(MLXNativeProvider())
        let released = await sink.unload(modelID: FoundationModelsProvider.modelID)
        XCTAssertFalse(released)
        let requests = await sink.releaseRequests
        XCTAssertEqual(requests, [], "an id this app cannot release is not recorded as released")
    }

    /// The release this app *can* perform is reported as performed, and recorded.
    func testTheSinkReleasesTheModelItWasToldAbout() async {
        let sink = OnDeviceUnloadSink()
        await sink.attach(MLXNativeProvider())
        let released = await sink.unload(modelID: MLXNativeProvider.modelID)
        XCTAssertTrue(released)
        let requests = await sink.releaseRequests
        XCTAssertEqual(requests, [MLXNativeProvider.modelID])
    }

    /// A sink that was never told about a provider cannot release one, and says so instead of reporting a
    /// success it did not perform.
    func testAnUnattachedProviderCannotBeReleased() async {
        let sink = OnDeviceUnloadSink()
        let released = await sink.unload(modelID: MLXNativeProvider.modelID)
        XCTAssertFalse(released)
        let requests = await sink.releaseRequests
        XCTAssertEqual(requests, [])
    }

    /// Warning-level pressure is answered with a flush, and an idle model keeps its container. Reloading a
    /// multi-gigabyte build is a worse answer to a nudge than this is.
    func testAWarningFlushesBuffersWithoutAskingForARelease() async {
        let sink = OnDeviceUnloadSink()
        await sink.attach(MLXNativeProvider())
        await sink.flushCaches()
        let requests = await sink.releaseRequests
        XCTAssertEqual(requests, [], "a flush is not a release")
    }

    /// An idle resident goes on the same critical event, through the unloader rather than by forgetting the
    /// id — the distinction that makes the release an event instead of a bookkeeping change.
    func testAnIdleResidentIsReleasedThroughTheUnloaderOnACriticalEvent() async {
        let releases = MemoryReleaseLog()
        let held = OnDeviceModelRegistry(
            memory: FixedMemoryReading(bytes: 8_000_000_000),
            unloader: { id in releases.record(id) }
        )
        let admission = OnDeviceMemoryAdmission(
            registry: held,
            memory: FixedMemoryReading(bytes: 8_000_000_000),
            footprint: { _ in
                MLXModelFootprint(weightsBytes: 1_070_000_000, layerCount: 36, kvHeadCount: 8, headDimension: 128)
            }
        )
        let here = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("release-wiring", isDirectory: true)
        _ = await admission.admitLoading(modelDirectory: here)
        await admission.turnFinished(modelDirectory: here)

        let released = await held.handleMemoryPressure(level: .critical)
        XCTAssertEqual(released, [MLXNativeProvider.modelID])
        XCTAssertEqual(releases.recorded, [MLXNativeProvider.modelID])
    }

    /// Leaving the foreground asks for the model back; staying in it does not. Backgrounding is the moment
    /// iOS starts deciding what to take, and the container is the largest thing this app is holding.
    func testBackgroundingAsksForTheModelAndForegroundDoesNot() async {
        let sink = OnDeviceUnloadSink()
        await sink.attach(MLXNativeProvider())

        await OnDeviceWiring.handlePhase(.active, sink: sink)
        await OnDeviceWiring.handlePhase(.inactive, sink: sink)
        var requests = await sink.releaseRequests
        XCTAssertEqual(requests, [], "only backgrounding releases")

        await OnDeviceWiring.handlePhase(.background, sink: sink)
        requests = await sink.releaseRequests
        XCTAssertEqual(requests, [MLXNativeProvider.modelID])
    }

    /// The engines the app actually registers: both on-device, neither leaves the device, and the sink can
    /// really release the MLX one — the loop that could not be closed at construction time.
    func testTheWiredEnginesAreOnDeviceAndReleasable() async {
        let held = OnDeviceModelRegistry(memory: FixedMemoryReading(bytes: 8_000_000_000))
        let sink = OnDeviceUnloadSink()
        let engines = await OnDeviceWiring.engines(registry: held, sink: sink)

        XCTAssertEqual(engines.count, 2)
        XCTAssertTrue(engines.allSatisfy { $0.networkClass == .onDevice })
        XCTAssertTrue(engines.allSatisfy { !$0.networkClass.leavesTheDevice })
        let released = await sink.unload(modelID: MLXNativeProvider.modelID)
        XCTAssertTrue(released, "engines() handed the MLX provider to the sink")
    }
}
