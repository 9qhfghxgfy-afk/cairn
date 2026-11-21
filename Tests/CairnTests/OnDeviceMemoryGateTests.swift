import XCTest
import CairnChatDomain
import CairnInferenceLocal
import CairnInferenceNative

/// The app-layer memory gate, proven where the arithmetic, the registry and the model store meet.
///
/// The arithmetic lives in `CairnInferenceLocal`, the runtime in `CairnInferenceNative`; neither can see
/// the folder of weights. This layer can, and it is the only place the two claims that matter can be
/// asserted: that a load is refused **before** a byte is allocated, and that a release asked for under a
/// running generation is deferred rather than dropped.
@MainActor
final class OnDeviceMemoryGateTests: XCTestCase {
    /// A 4-bit 4-billion-parameter build, from the model's own published shape.
    private var measuredFiles: MLXModelFootprint? {
        MLXModelFootprint(weightsBytes: 1_070_000_000, layerCount: 36, kvHeadCount: 8, headDimension: 128)
    }

    private let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("memory-gate", isDirectory: true)

    private func registry(
        _ headroomBytes: Int64?, releases: MemoryReleaseLog? = nil
    ) -> OnDeviceModelRegistry {
        OnDeviceModelRegistry(
            memory: FixedMemoryReading(bytes: headroomBytes),
            unloader: { id in releases?.record(id) }
        )
    }

    private func gate(
        _ headroomBytes: Int64?, files: MLXModelFootprint?, into held: OnDeviceModelRegistry
    ) -> OnDeviceMemoryAdmission {
        OnDeviceMemoryAdmission(
            registry: held,
            memory: FixedMemoryReading(bytes: headroomBytes),
            footprint: { _ in files }
        )
    }

    /// Files that cannot be sized are a refusal, not a zero: a phone that cannot report the size of its
    /// own model folder is mid-delete or out of storage.
    func testAGateThatCannotSizeTheFilesRefusesTheLoad() async {
        let held = registry(8_000_000_000)
        let verdict = await gate(8_000_000_000, files: nil, into: held)
            .admitLoading(modelDirectory: directory)
        guard case .refuse(let reason) = verdict else {
            return XCTFail("an unmeasurable model must not be admitted: \(verdict)")
        }
        XCTAssertFalse(reason.isEmpty)
        let residents = await held.residentModels()
        XCTAssertTrue(residents.isEmpty, "a refusal leaves nothing resident")
    }

    /// A missing headroom reading is unknown, never unlimited — the rule the two-resident answer already
    /// holds to, now applied to the load itself.
    func testAnUnknownHeadroomReadingRefusesTheLoad() async {
        let held = registry(nil)
        let verdict = await gate(nil, files: measuredFiles, into: held)
            .admitLoading(modelDirectory: directory)
        guard case .refuse = verdict else {
            return XCTFail("unknown headroom must not be read as room: \(verdict)")
        }
    }

    /// A measured reading admits, and the pool it asks for is capped rather than left at the runtime's own
    /// default, which the pinned package documents as 1.5× the recommended working set.
    func testAMeasuredReadingAdmitsAndCapsTheBufferPool() async {
        let held = registry(8_000_000_000)
        let verdict = await gate(8_000_000_000, files: measuredFiles, into: held)
            .admitLoading(modelDirectory: directory)
        guard case .admit(let cacheLimitBytes) = verdict else {
            return XCTFail("a roomy reading should admit: \(verdict)")
        }
        XCTAssertGreaterThan(cacheLimitBytes, 0)
        XCTAssertLessThanOrEqual(cacheLimitBytes, 32 * 1024 * 1024)
        let residents = await held.residentModels().map(\.modelID)
        XCTAssertEqual(residents, [MLXNativeProvider.modelID], "an admitted load is recorded as resident")
    }

    /// The rule that turned into a jetsam kill, end to end: pressure arriving mid-generation does not take
    /// the model out from under it, and the release lands when the turn ends.
    func testPressureUnderARunningGenerationIsDeferredAndThenLands() async {
        let releases = MemoryReleaseLog()
        let held = registry(8_000_000_000, releases: releases)
        let admission = gate(8_000_000_000, files: measuredFiles, into: held)
        _ = await admission.admitLoading(modelDirectory: directory)

        let releasedWhileBusy = await held.handleMemoryPressure(level: .critical)
        XCTAssertTrue(releasedWhileBusy.isEmpty, "a busy model is not taken mid-stream")
        XCTAssertEqual(releases.recorded, [])

        await admission.turnFinished(modelDirectory: directory)
        XCTAssertEqual(releases.recorded, [MLXNativeProvider.modelID], "the deferred release lands")
        let residents = await held.residentModels()
        XCTAssertTrue(residents.isEmpty)
    }
}

/// Release calls that reached the app's unloader, by id — typed metadata, never model content.
/// `@unchecked Sendable` because its only state is the list behind this lock, and `NSLock.lock()` is
/// unavailable inside the async unloader that calls it.
final class MemoryReleaseLog: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [String] = []

    func record(_ id: String) {
        lock.lock(); ids.append(id); lock.unlock()
    }

    var recorded: [String] {
        lock.lock(); defer { lock.unlock() }; return ids
    }
}
