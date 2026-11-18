import CairnChatDomain
import Foundation
import Testing
@testable import CairnInferenceLocal

/// The two-resident answer, tested where the reading is made. What is pinned here is that every
/// answer of "yes" is a measurement: unknown, zero, tight, and overflowing readings all say no.
struct TwoResidentBudgetTests {
    private let footprint = TwoResidentBudget.conservativeModelFootprintBytes

    @Test func unknownReadingIsNeverReadAsUnlimited() {
        #expect(TwoResidentBudget.allowsTwoResident(headroomBytes: nil) == false)
        #expect(TwoResidentBudget.allowsTwoResident(headroomBytes: 0) == false)
        #expect(TwoResidentBudget.allowsTwoResident(headroomBytes: -1) == false)
    }

    @Test func aTightReadingRefusesTheSecondResident() {
        // Both sides need 2 × footprint inside 4/5 of headroom. 2.0 GB of headroom leaves 1.6 GB
        // usable, which is one model and not two.
        #expect(TwoResidentBudget.allowsTwoResident(headroomBytes: 2_000_000_000) == false)
        // Exactly one model's share is still one model, not two.
        #expect(
            TwoResidentBudget.allowsTwoResident(
                headroomBytes: footprint * 2,  // 4/5 of this is still below 2 × footprint
                modelFootprintBytes: footprint
            ) == false
        )
    }

    @Test func measuredRoomForBothInsideTheUsableShareAdmitsTwo() {
        // 4.0 GB of headroom → 3.2 GB usable ≥ 2 × 1.5 GB.
        #expect(TwoResidentBudget.allowsTwoResident(headroomBytes: 4_000_000_000))
        #expect(
            TwoResidentBudget.allowsTwoResident(
                headroomBytes: 1_000_000_000, modelFootprintBytes: 400_000_000
            )
        )
    }

    @Test func anAbsurdFootprintSaturatesToNoRatherThanWrappingIntoYes() {
        #expect(
            TwoResidentBudget.allowsTwoResident(
                headroomBytes: Int64.max, modelFootprintBytes: Int64.max
            ) == false
        )
    }
}

struct OnDeviceResidencyGateTests {
    private func model(_ id: String, footprint: Int64 = 1_000_000_000) -> ResidentModel {
        ResidentModel(
            modelID: id, runtime: .mlx, weightsBytes: footprint,
            footprintBytes: footprint, contextLength: 4096
        )
    }

    @Test func unknownHeadroomRefusesTwoResidents() {
        let gate = OnDeviceResidencyGate(
            registry: OnDeviceModelRegistry(memory: FixedMemoryReading(bytes: nil)),
            memory: FixedMemoryReading(bytes: nil)
        )
        #expect(gate.allowsTwoOnDeviceModelsResident() == false)
    }

    @Test func aTightReadingRefusesAndTheSchedulerThenSerialisesBothSides() {
        let gate = OnDeviceResidencyGate(
            registry: OnDeviceModelRegistry(memory: FixedMemoryReading(bytes: 2_000_000_000)),
            memory: FixedMemoryReading(bytes: 2_000_000_000)
        )
        #expect(gate.allowsTwoOnDeviceModelsResident() == false)
        // The refusal has to reach the schedule, or it is only an opinion.
        let groups = HybridScheduling.candidateGroups(
            networkClasses: [.onDevice, .onDevice],
            allowsTwoOnDeviceModelsResident: gate.allowsTwoOnDeviceModelsResident()
        )
        #expect(groups.count == 2)
        #expect(groups.allSatisfy { $0.indexes.count == 1 && $0.concurrent == false })
    }

    @Test func evictionReleasesEveryModelTheRegistryOwnsThroughTheUnloader() async {
        let calls = Recorder()
        let registry = OnDeviceModelRegistry(
            memory: FixedMemoryReading(bytes: 8_000_000_000),
            unloader: { id in calls.record(id) }
        )
        await registry.markLoaded(model("first"))
        let gate = OnDeviceResidencyGate(
            registry: registry, memory: FixedMemoryReading(bytes: 8_000_000_000)
        )

        await gate.evictResidentModel()
        #expect(calls.recorded == ["first"])
        #expect(await registry.residentModels().isEmpty)
    }

    @Test func theGateReReadsHeadroomOnEveryQuestion() async {
        // The first answer is yes. Once the device takes the budget back the same gate has to say
        // no, which it can only do by asking the reading again rather than caching the first one.
        let memory = FlipMemoryReading()
        let gate = OnDeviceResidencyGate(
            registry: OnDeviceModelRegistry(memory: memory), memory: memory
        )
        memory.set(bytes: 8_000_000_000)
        #expect(gate.allowsTwoOnDeviceModelsResident())

        memory.set(bytes: nil)
        #expect(gate.allowsTwoOnDeviceModelsResident() == false)
        #expect(memory.readCount == 2)
    }
}

/// A reading a test moves under the gate, so "re-read at decision time" is proven instead of
/// asserted. Reading count is part of the assertion: a gate that cached one answer would never
/// reach the second read.
final class FlipMemoryReading: MemoryReading, @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: Int64?
    private var reads = 0

    func set(bytes: Int64?) {
        lock.lock(); self.bytes = bytes; lock.unlock()
    }

    func availableMemoryBytes() -> Int64? {
        lock.lock(); defer { reads += 1; lock.unlock() }
        return bytes
    }

    var readCount: Int {
        lock.lock(); defer { lock.unlock() }; return reads
    }
}
