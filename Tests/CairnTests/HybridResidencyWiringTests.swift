import XCTest
import CairnChatDomain
import CairnInferenceLocal

/// The memory answer a hybrid turn asks, proven against a real `OnDeviceModelRegistry` rather than a
/// stub. The rule under test decides whether the phone runs both sides of a hybrid turn at once or one
/// after the other: two sets of weights in this process are allowed only on a fresh, positive reading
/// that fits both, and when they must take turns the release between them is an event.
///
/// Every reading here is injected. `os_proc_available_memory()` has no macOS equivalent, so a host
/// build reads `nil`, which is treated as unknown and never as unlimited — there is no simulated
/// ceiling this machine cannot produce.
@MainActor
final class HybridResidencyWiringTests: XCTestCase {

    private let footprint = TwoResidentBudget.conservativeModelFootprintBytes

    private func registry(
        _ headroomBytes: Int64?, unloader: ResidencyRecorder? = nil
    ) -> OnDeviceModelRegistry {
        OnDeviceModelRegistry(
            memory: FixedMemoryReading(bytes: headroomBytes),
            unloader: { id in unloader?.record(id) }
        )
    }

    private func gate(_ headroomBytes: Int64?) -> OnDeviceResidencyGate {
        OnDeviceResidencyGate(
            registry: registry(headroomBytes), memory: FixedMemoryReading(bytes: headroomBytes)
        )
    }

    /// "The platform declined to say" is not a licence. This is the case a build without the
    /// increased-memory entitlement lands in whenever the reading comes back low or absent.
    func testAnUnknownReadingNeverReadsAsLicenceToLoadTwoModels() {
        XCTAssertFalse(gate(nil).allowsTwoOnDeviceModelsResident())
        XCTAssertFalse(gate(0).allowsTwoOnDeviceModelsResident())
        XCTAssertFalse(gate(-1).allowsTwoOnDeviceModelsResident())
    }

    /// The boundary is two footprints inside the usable four-fifths, asserted at the exact byte: enough
    /// reads yes, one byte short reads no. A gate that rounds toward "yes" is the one that gets the app
    /// killed between the first candidate and the second.
    func testTheBoundaryIsMeasuredNotApproximated() {
        let exact = footprint * 2 * 5 / 4
        XCTAssertTrue(gate(exact).allowsTwoOnDeviceModelsResident())
        XCTAssertFalse(gate(exact - 1).allowsTwoOnDeviceModelsResident(), "one byte short is short")
        XCTAssertTrue(gate(footprint * 8).allowsTwoOnDeviceModelsResident())
    }

    /// Every gate answers from the reading it is handed, asserted at the byte where the usable share
    /// stops covering two footprints. That the *same* gate asks the reading again instead of caching
    /// one verdict is proven where the reading is made — `TwoResidentBudgetTests` moves a reading
    /// under the gate and counts the reads. A cached verdict would keep promising a second model
    /// after the headroom had been withdrawn.
    func testTheAnswerFollowsTheReadingRatherThanACachedVerdict() {
        let room = gate(footprint * 8)
        let tight = gate(footprint)
        XCTAssertTrue(room.allowsTwoOnDeviceModelsResident())
        XCTAssertFalse(tight.allowsTwoOnDeviceModelsResident())
        XCTAssertFalse(gate(footprint / 2).allowsTwoOnDeviceModelsResident())
    }

    /// "Sequentially, with a clean release between them" has to be an event rather than two loads that
    /// happen to miss each other in time. The gate's eviction goes through the registry, which calls the
    /// runtime's unloader for every model this process owns and then reports nothing resident.
    func testEvictionReallyUnloadsWhatIsHeld() async throws {
        let calls = ResidencyRecorder()
        let held = registry(nil, unloader: calls)
        let gate = OnDeviceResidencyGate(registry: held, memory: FixedMemoryReading(bytes: nil))

        await held.markLoaded(
            ResidentModel(modelID: "mlx-8b", runtime: .mlx, weightsBytes: footprint,
                          footprintBytes: footprint, contextLength: 4096)
        )
        XCTAssertTrue(await held.isResident("mlx-8b"))

        await gate.evictResidentModel()

        XCTAssertEqual(calls.recorded, ["mlx-8b"], "the runtime was told, not just the bookkeeping")
        XCTAssertTrue(await held.residentModels().isEmpty, "nothing is left held")
    }

    /// The scheduling decision a hybrid turn really takes, driven by the gate object instead of a bool
    /// written by hand: two on-device sides with unknown headroom never overlap, and each turn of the
    /// sequence is a single candidate.
    func testTwoOnDeviceSidesAreScheduledOneAtATimeOnAnUnknownReading() {
        let groups = HybridScheduling.candidateGroups(
            networkClasses: [.onDevice, .onDevice],
            allowsTwoOnDeviceModelsResident: gate(nil).allowsTwoOnDeviceModelsResident()
        )
        XCTAssertEqual(groups, [
            HybridRunGroup(indexes: [0], concurrent: false),
            HybridRunGroup(indexes: [1], concurrent: false),
        ])
    }

    /// And the other way round: on a measured reading with room, both sides do run together — the whole
    /// reason to ask the question instead of refusing it.
    func testTwoOnDeviceSidesRunTogetherOnAMeasuredReading() {
        let groups = HybridScheduling.candidateGroups(
            networkClasses: [.onDevice, .onDevice],
            allowsTwoOnDeviceModelsResident: gate(footprint * 8).allowsTwoOnDeviceModelsResident()
        )
        XCTAssertEqual(groups, [HybridRunGroup(indexes: [0, 1], concurrent: true)])
    }

    /// A remote side costs a socket, not weights, so it needs no headroom and owes no release. Asking
    /// the memory question must not turn into refusing every mixed turn — that would be the cheap
    /// answer that makes Hybrid Parallel useless on the phone against a server.
    func testAMixedPairNeedsNoHeadroomAtAll() {
        let groups = HybridScheduling.candidateGroups(
            networkClasses: [.publicInternet, .onDevice],
            allowsTwoOnDeviceModelsResident: gate(nil).allowsTwoOnDeviceModelsResident()
        )
        XCTAssertEqual(groups, [HybridRunGroup(indexes: [0, 1], concurrent: true)])
        XCTAssertTrue(
            HybridScheduling.synthesisNeedsRelease(
                synthesizerClass: .onDevice, candidatesRanOnDevice: true
            ),
            "an on-device writer after an on-device candidate still owes a release"
        )
    }
}
