import XCTest
import CairnChatDomain
import CairnInferenceLocal

/// The app layer's own residency factory, compiled straight into this test bundle by `project.yml`
/// because it is the wiring M4 promises and carries no `@main`. Two claims are pinned: the gate it
/// builds agrees with the pure budget for whatever the platform really reports — there is no invented
/// ceiling anywhere in the app — and the release it performs actually reaches the runtime.
@MainActor
final class HybridWiringFactoryTests: XCTestCase {

    private func registry(
        _ memory: any MemoryReading, unloader: ResidencyRecorder? = nil
    ) -> OnDeviceModelRegistry {
        OnDeviceModelRegistry(memory: memory, unloader: { id in unloader?.record(id) })
    }

    /// The factory is not allowed to hold its own opinion about memory. Whatever the device reports, the
    /// pure budget decides — on a host build that reading is `nil` and the answer is no, which this
    /// asserts without pretending this machine has a ceiling it cannot measure.
    func testTheWiredGateAgreesWithTheBudgetOnTheRealReading() {
        let reading = SystemMemoryReading().availableMemoryBytes()
        let wired = HybridWiring.residencyGate(registry(SystemMemoryReading()))
        XCTAssertEqual(
            wired.allowsTwoOnDeviceModelsResident(),
            TwoResidentBudget.allowsTwoResident(headroomBytes: reading),
            "the wired gate is the budget, not a second rule"
        )
        XCTAssertEqual(
            HybridWiring.allowsTwoOnDeviceModelsResident(),
            TwoResidentBudget.allowsTwoResident(headroomBytes: reading)
        )
    }

    /// The same rule with the reading supplied, so the boundary is proven on this machine even though a
    /// simulator's own ceiling is not something a test may choose.
    func testTheWiredRuleRefusesWithoutAMeasuredFit() {
        let footprint = TwoResidentBudget.conservativeModelFootprintBytes
        XCTAssertFalse(HybridWiring.allowsTwoOnDeviceModelsResident(memory: FixedMemoryReading(bytes: nil)))
        XCTAssertFalse(HybridWiring.allowsTwoOnDeviceModelsResident(memory: FixedMemoryReading(bytes: footprint)))
        XCTAssertTrue(
            HybridWiring.allowsTwoOnDeviceModelsResident(
                memory: FixedMemoryReading(bytes: footprint * 2 * 5 / 4)
            )
        )
    }

    /// A wired gate releases through the registry it was built with, which is the same registry the
    /// memory-pressure watch uses — one owner for on-device memory, not one per feature.
    func testTheWiredGateReleasesThroughItsRegistry() async throws {
        let calls = ResidencyRecorder()
        let held = registry(FixedMemoryReading(bytes: nil), unloader: calls)
        await held.markLoaded(
            ResidentModel(modelID: "mlx-3b", runtime: .mlx, weightsBytes: 1,
                          footprintBytes: 1, contextLength: 4096)
        )

        await HybridWiring.residencyGate(held).evictResidentModel()

        XCTAssertEqual(calls.recorded, ["mlx-3b"])
        XCTAssertTrue(await held.residentModels().isEmpty)
    }
}
