import XCTest
import CairnChatDomain
import CairnAppUI

/// The merged Installed list, proved at the view model where the merge rule actually lives.
///
/// The rules worth holding are the ones a screenshot of a working screen cannot show: a phone with models
/// on disk still shows them when a server refuses, one name on two hosts stays two rows, and a Delete only
/// ever exists where deleting is something Cairn can do. The view layer is a ForEach over these arrays, so
/// testing here reaches the whole feature.
@MainActor
final class ModelInstalledSectionTests: XCTestCase {

    private func phoneEntry(_ repoID: String, size: Int64? = 1_000_000_000) -> InstalledModelEntry {
        InstalledModelEntry(
            id: InstalledModelEntry.phoneID(repoID: repoID),
            displayName: repoID,
            format: .gguf,
            host: .thisPhone,
            hostModelID: repoID,
            sizeBytes: size
        )
    }

    private var systemEntry: InstalledModelEntry {
        InstalledModelEntry(
            id: InstalledModelEntry.systemID,
            displayName: "Apple Intelligence",
            format: .appleIntelligence,
            host: .system
        )
    }

    private func makeModel(
        serving: InstalledStubServing?,
        service: StubModelService = StubModelService()
    ) -> ModelManagerModel {
        let model = ModelManagerModel(managing: service, lifecycle: InstalledStubLifecycle())
        model.installedServing = serving
        return model
    }

    private var profile: ServerProfile {
        ServerProfile(name: "Studio box", kind: .ollama, baseURLString: "http://192.168.1.20:11434")
    }

    func testAPhoneWithModelsOnDiskIsNotShownEmptyBecauseAServerRefused() async {
        let service = StubModelService()
        service.failure = ModelLifecycleError.optInRequired
        let serving = InstalledStubServing()
        serving.entries = [phoneEntry("org/gguf"), systemEntry]
        let model = makeModel(serving: serving, service: service)

        await model.open(profile)

        XCTAssertEqual(model.installedEntries.map(\.id), [InstalledModelEntry.phoneID(repoID: "org/gguf"),
                                                         InstalledModelEntry.systemID])
        XCTAssertNotNil(model.notice, "the server's refusal is still reported, just not as an empty list")
    }

    func testOneNameOnAPhoneAndOnAServerStaysTwoRows() async {
        let serving = InstalledStubServing()
        // The same tag the server reports, as a folder on this phone.
        serving.entries = [phoneEntry("qwen3:8b")]
        let model = makeModel(serving: serving)

        await model.open(profile)

        XCTAssertEqual(model.installedEntries.count, 2)
        XCTAssertEqual(model.installedEntries.map(\.host), [.thisPhone, .remoteServer])
        XCTAssertEqual(model.installedEntries.map(\.badgeText), ["GGUF", "Server"])
    }

    func testAServerRowsOwnerIsNamedAndItsRowsAreNotDeletable() async {
        let model = makeModel(serving: InstalledStubServing())
        await model.open(profile)
        let server = model.installedEntries.first { $0.host == .remoteServer }
        XCTAssertEqual(server?.sourceName, "Studio box")
        XCTAssertEqual(server?.id, "server:\(profile.id):qwen3:8b")
        XCTAssertFalse(model.deletionVerdict(for: server ?? phoneEntry("x")).isAllowed)
    }

    func testDeletingAPhoneRowTellsTheStoreAndBothScreensAreTold() async {
        let serving = InstalledStubServing()
        serving.entries = [phoneEntry("org/gguf")]
        serving.entriesAfterRemoval = []
        let model = makeModel(serving: serving)
        let hook = InstalledRemovalHook()
        model.onLocalModelRemoved = { entry in await hook.record(entry) }

        await model.open(profile)
        XCTAssertEqual(model.installedEntries.count, 1)

        await model.removeInstalled(model.installedEntries[0])

        XCTAssertEqual(serving.removals, [InstalledModelEntry.phoneID(repoID: "org/gguf")])
        XCTAssertEqual(hook.ids, ["org/gguf"], "the screens are told which repository went away")
        XCTAssertTrue(model.installedEntries.isEmpty, "the row is gone once the store says it is")
    }

    func testARefusedRemovalLeavesTheRowOnScreenWithTheReason() async throws {
        let serving = InstalledStubServing()
        serving.entries = [phoneEntry("org/gguf")]
        let model = makeModel(serving: serving)

        await model.open(profile)
        let entry = try XCTUnwrap(model.installedEntries.first)

        // The store refuses because a turn is being written in that model. The read still works, so the row
        // can only still be here because the store still has it — not because a refresh failed and fell back.
        serving.removeFailure = InstalledModelError.turnRunning
        await model.removeInstalled(entry)

        XCTAssertEqual(model.notice, InstalledModelError.turnRunning.errorDescription)
        XCTAssertEqual(model.installedEntries.map(\.id), [entry.id],
                       "a delete that did not happen leaves the row where it was")
        XCTAssertTrue(serving.removals.isEmpty)
    }

    func testAStoreThatWillNotReadKeepsTheRowsItAlreadyShowed() async throws {
        let serving = InstalledStubServing()
        serving.entries = [phoneEntry("org/gguf")]
        let model = makeModel(serving: serving)
        await model.open(profile)
        let entry = try XCTUnwrap(model.installedEntries.first)

        serving.listFailure = CairnInstalledProbeFailure()
        await model.refreshInstalledEntries()

        XCTAssertEqual(model.installedEntries.map(\.id), [entry.id],
                       "a store that cannot be read now is not evidence that the folder is gone")
        XCTAssertEqual(model.notice, CairnInstalledProbeFailure().errorDescription,
                       "the notice is the read's own failure, not a removal's")
    }

    func testWithoutAStoreWiredTheTabShowsTheServersAnswerAndSaysSo() async {
        let model = makeModel(serving: nil)
        await model.open(profile)
        XCTAssertFalse(model.servingLocalModels)
        XCTAssertEqual(model.installedEntries.count, 1, "the server's own list is still shown")
        XCTAssertEqual(model.installedEntries.first?.host, .remoteServer)
    }

    func testAPhoneRowNeverAsksAServerForDetail() async {
        let serving = InstalledStubServing()
        serving.entries = [phoneEntry("qwen3:8b")]
        let lifecycle = InstalledStubLifecycle()
        let model = ModelManagerModel(managing: StubModelService(), lifecycle: lifecycle)
        model.installedServing = serving
        await model.open(profile)

        await model.inspectRemote(model.installedEntries.first { $0.host == .thisPhone }!)
        XCTAssertTrue(lifecycle.detailRequests.isEmpty,
                      "a folder on this phone has no detail endpoint to ask")
    }

    func testVerdictsAreDerivedFromTheEntryRatherThanFromACallersClaim() {
        XCTAssertTrue(ModelDeletion.verdict(for: phoneEntry("a")).isAllowed)
        XCTAssertFalse(ModelDeletion.verdict(for: systemEntry).isAllowed)
        let forged = InstalledModelEntry(
            id: "phone:apple", displayName: "Apple Intelligence",
            format: .appleIntelligence, host: .thisPhone, hostModelID: "apple"
        )
        XCTAssertFalse(ModelDeletion.verdict(for: forged).isAllowed,
                       "a hand-built row cannot give itself a Delete button")
    }
}

/// The phone's half, as the App layer hands it over: a list, and a removal that records what it was asked
/// to take back.
@MainActor
final class InstalledStubServing: InstalledModelServing {
    var entries: [InstalledModelEntry] = []
    /// Two separate failures on purpose. One error field would make a refusal test pass for the wrong
    /// reason: if the same flag makes both `remove` and the following read throw, the notice the test
    /// asserts could have come from either, and the row surviving could be the fallback rather than the
    /// store still holding it.
    var removeFailure: Error?
    var listFailure: Error?
    var removals: [String] = []
    /// What the list answers after a removal — a real store re-reads the folder, so a deleted model must
    /// come back gone rather than merely unanswered.
    var entriesAfterRemoval: [InstalledModelEntry] = []

    func installedEntries() async throws -> [InstalledModelEntry] {
        if let listFailure { throw listFailure }
        return removals.isEmpty ? entries : entriesAfterRemoval
    }

    func remove(_ entry: InstalledModelEntry) async throws {
        if let removeFailure { throw removeFailure }
        removals.append(entry.id)
    }
}

/// Lifecycle off the path under test, recorded so a phone row can be proved to ask the server nothing.
@MainActor
final class InstalledStubLifecycle: ModelLifecycleManaging {
    var detailRequests: [String] = []
    var detailToReturn: ModelDetail?

    func supportsLifecycle(_ profile: ServerProfile) -> Bool { true }
    func guidance(_ profile: ServerProfile) -> String { "Lifecycle is available here." }
    func runningModels(_ profile: ServerProfile) async throws -> [ResidentServerModel] { [] }

    func detail(model: String, profile: ServerProfile) async throws -> ModelDetail {
        detailRequests.append(model)
        if let detailToReturn { return detailToReturn }
        return ModelDetail(id: model)
    }

    func pull(model: String, profile: ServerProfile) -> AsyncThrowingStream<ModelPullProgress, any Error> {
        AsyncThrowingStream<ModelPullProgress, any Error> { $0.finish() }
    }

    func loadModel(model: String, profile: ServerProfile) async throws {}
    func unload(model: String, profile: ServerProfile) async throws {}
    func delete(model: String, profile: ServerProfile) async throws {}
}

/// Records what the removal hook was told, so the assertion is about the App layer's contract rather than
/// about a captured local — an object that outlives the call is also what the real wiring holds.
@MainActor
final class InstalledRemovalHook {
    var ids: [String] = []

    func record(_ entry: InstalledModelEntry) async {
        ids.append(entry.hostModelID ?? "")
    }
}

/// A failure that is not one of the deletion refusals, so a notice asserted after a failed read can only
/// have come from the read.
struct CairnInstalledProbeFailure: LocalizedError {
    var errorDescription: String? { "The model store could not be read." }
}
