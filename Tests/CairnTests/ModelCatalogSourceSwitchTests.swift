import XCTest
import CairnChatDomain
import CairnAppUI

/// The Download tab's source rules, proved against the real view model with no server and no network.
///
/// The rules worth holding are the ones a screenshot cannot show: the tab opens on the library that
/// belongs to whoever opened Models, a hand-moved switch outranks that guess, and a tag pointed at a
/// server with no install endpoint never starts a pull until a server that can run one is named.
@MainActor
final class ModelCatalogSourceSwitchTests: XCTestCase {

    private func row(_ id: String, origin: ModelCatalogOrigin) -> LocalCatalogRow {
        LocalCatalogRow(repoID: id, displayName: id, summary: "A stub row.",
                        downloadBytes: 1_000,
                        sortOrder: 0, origin: origin)
    }

    private func makeModel(granted: Bool = false) -> (ModelCatalogModel, SourceStubLibrary) {
        let library = SourceStubLibrary(rows: [row("mlx-community/Phone", origin: .onDevice)])
        let built = ModelCatalogModel(
            library: library,
            servers: nil,
            traffic: .memory(granted: granted),
            ollamaTargets: {
                [ServerProfile(name: "Home Ollama", kind: .ollama, baseURLString: "http://192.168.1.20:11434")]
            }
        )
        return (built, library)
    }

    /// A hand-moved switch outranks whatever the opening server implies, which is the rule that keeps the
    /// tab from moving back under the user on the next visit.
    func testOpeningFollowsTheServerUntilTheUserChooses() async {
        let (model, _) = makeModel()
        await model.openFrom(kind: nil)
        XCTAssertEqual(model.destination, .onDevice, "On-Device opens on Hugging Face")
        XCTAssertEqual(model.sourceLabel, "Hugging Face")

        await model.choose(.ollamaLibrary)
        XCTAssertTrue(model.sourceChosen)

        await model.openFrom(kind: .openAICompatible)
        XCTAssertEqual(model.destination, .ollamaLibrary, "a chosen source is not moved by a later visit")
    }

    /// The Ollama library is never empty, and a typed name is still offered as its own card — in the
    /// shape that source can actually install.
    func testBothSourcesOpenPopulated() async {
        let (model, _) = makeModel()
        await model.openFrom(kind: .ollama)
        XCTAssertFalse(model.rows.isEmpty, "a remote server must not open an empty Download tab")
        XCTAssertTrue(model.rows.allSatisfy { !$0.origin.landsOnThisPhone })

        model.filter.search = "custom:latest"
        XCTAssertEqual(model.visibleRows.last?.origin, .custom, "a tag is what an Ollama server takes")
        model.filter.search = "someone/New-Repo"
        XCTAssertNotEqual(model.visibleRows.last?.origin, .custom,
                          "an owner/repository id is not a tag, so it must not be offered here")

        await model.choose(.onDevice)
        model.filter.search = "someone/New-Repo"
        XCTAssertEqual(model.visibleRows.last?.origin, .custom, "the phone path needs the repository shape")
    }

    /// A server that lists models but has no install endpoint cannot take a pull, so the sheet has to
    /// name one before the button is real.
    func testAServerThatCannotPullBlocksTheTagUntilOneIsNamed() async {
        let (model, _) = makeModel(granted: true)
        await model.openFrom(kind: .openAICompatible)
        XCTAssertTrue(model.needsAnotherServer, "an OpenAI-compatible server has no install endpoint")
        XCTAssertNil(model.pullTarget)

        let choices = model.ollamaChoices
        XCTAssertEqual(choices.count, 1, "only the configured Ollama servers are offered")
        model.choosePullTarget(choices[0])
        XCTAssertEqual(model.pullDestination?.name, "Home Ollama")
    }

    /// One tap both grants the acknowledgement and starts the download it authorises.
    func testAllowAndDownloadGrantsAndStartsInOneTap() {
        let (model, library) = makeModel(granted: false)
        let subject = row("mlx-community/Phone", origin: .onDevice)
        XCTAssertFalse(model.weightsAreAllowed)

        model.allowAndDownload(subject)

        XCTAssertTrue(model.weightsAreAllowed, "the tap that starts the download is the grant")
        XCTAssertEqual(library.downloadCalls, ["mlx-community/Phone"])
    }

    /// Refusing is reversible, and refusing after granting takes the grant back.
    func testTheGrantIsTakenBackByTheSameSwitch() {
        let (model, _) = makeModel(granted: false)
        model.allowAndDownload(row("mlx-community/Phone", origin: .onDevice))
        model.denyWeights()
        XCTAssertFalse(model.weightsAreAllowed)
    }
}

/// A library that answers from memory and records what it was asked to fetch.
@MainActor
private final class SourceStubLibrary: LocalModelLibraryServicing {
    var rows: [LocalCatalogRow]
    var downloadCalls: [String] = []

    init(rows: [LocalCatalogRow]) { self.rows = rows }

    func catalogRows() async throws -> [LocalCatalogRow] { rows }
    func installedRows() async throws -> [InstalledLocalModel] { [] }
    func delete(_ model: InstalledLocalModel) async throws {}

    func pauseDownload(repoID: String) async {}
    func cancelDownload(repoID: String) async throws {}
    func discard(repoID: String) async throws {}
    func keepsPartialTransfer(repoID: String) async -> Bool { false }

    func download(_ row: LocalCatalogRow) -> AsyncThrowingStream<LocalTransferState, any Error> {
        downloadCalls.append(row.repoID)
        return AsyncThrowingStream { continuation in
            continuation.yield(.installed(bytes: 1_000))
            continuation.finish()
        }
    }
}
