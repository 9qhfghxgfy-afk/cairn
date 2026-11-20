import XCTest
import CairnChatDomain
import CairnAppUI

/// The Download library's view model, proved without a simulator or a network.
///
/// The rules worth holding are the ones a screenshot cannot show: a download that must not start because
/// the device has not agreed to the traffic, a card that keeps its own numbers rather than another model's,
/// chips that only ever narrow, and an installed mark that comes from the store rather than from a name that
/// sounds familiar.
@MainActor
final class ModelCatalogDownloadTests: XCTestCase {

    private func stubRows() -> [LocalCatalogRow] {
        // Argument order follows `LocalCatalogRow.init` exactly: a labelled argument list that is out of
        // declaration order is a compile error, and this target only ever gets compiled on CI.
        [
            LocalCatalogRow(repoID: "mlx-community/Big Model", displayName: "Big Model",
                            summary: "A large capable build.",
                            downloadBytes: 8_000_000_000,
                            capabilityLabels: ["Tools", "Vision"],
                            provider: "Example", series: "Big",
                            sortOrder: 1, origin: .onDevice),
            LocalCatalogRow(repoID: "mlx-community/Small Quiet", displayName: "Small Quiet",
                            summary: "A small text-only build.",
                            downloadBytes: 900_000_000,
                            provider: "Example", series: "Quiet",
                            sortOrder: 2, origin: .onDevice),
        ]
    }

    private func makeModel(
        granted: Bool,
        rows: [LocalCatalogRow]? = nil
    ) -> (ModelCatalogModel, StubLibrary) {
        let library = StubLibrary(rows: rows ?? stubRows())
        let built = ModelCatalogModel(
            library: library,
            servers: nil,
            traffic: .memory(granted: granted)
        )
        return (built, library)
    }

    /// Lets the download task come to rest. It finishes as soon as the stub's stream does; the poll is here
    /// because the task is deliberately not exposed, and a fixed sleep would make the suite both slow and
    /// flaky at once.
    private func settle(_ model: ModelCatalogModel) async {
        for _ in 0..<100 {
            if !model.isDownloading { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("the transfer never came to rest")
    }

    func testRefreshShowsWhatTheStoreSaysIsInstalled() async {
        let (model, library) = makeModel(granted: false)
        await model.refresh()
        XCTAssertEqual(model.rows.count, 2)
        XCTAssertTrue(model.rows.allSatisfy { !$0.isInstalled })
        library.rows = library.rows.map { $0.marking(installed: true) }
        await model.refresh()
        XCTAssertTrue(model.rows.allSatisfy(\.isInstalled))
    }

    func testNothingIsFetchedUntilTheTrafficIsAgreedToAndTheReasonIsNamed() {
        let (model, library) = makeModel(granted: false)
        model.download(stubRows()[0])
        XCTAssertTrue(library.downloadCalls.isEmpty,
                      "a download that has not been agreed to must not even ask for a file list")
        XCTAssertEqual(model.notice, ModelCatalogModel.trafficNotice)
        XCTAssertFalse(model.isDownloading)
    }

    func testTheCardCarriesItsOwnNumbersAndLandsInstalled() async {
        let (model, library) = makeModel(granted: true)
        await model.refresh()
        let row = model.rows.first { $0.repoID == "mlx-community/Big Model" }!
        model.download(row)
        XCTAssertEqual(library.downloadCalls, ["mlx-community/Big Model"])
        await settle(model)
        let status = model.status(for: row)
        XCTAssertEqual(status?.stage, .finished)
        XCTAssertEqual(status?.completedBytes, 1_000)
        XCTAssertFalse(model.isDownloading)
        XCTAssertTrue(model.rows.first { $0.repoID == row.repoID }?.isInstalled ?? false,
                      "the re-read list must say the model is here")
        XCTAssertTrue(model.focused?.isInstalled ?? false,
                      "the open sheet must not keep describing the state as it was")
    }

    func testAStatusNeverDescribesAnotherModel() async {
        let (model, _) = makeModel(granted: true)
        await model.refresh()
        model.download(model.rows[0])
        let other = LocalCatalogRow(repoID: "mlx-community/Someone Else", displayName: "Someone Else")
        XCTAssertNil(model.status(for: other))
        await settle(model)
    }

    func testCancelLeavesTheRowStoppedRatherThanFailed() async {
        let library = StubLibrary(rows: stubRows(),
                                  script: [.running(doneBytes: 1, totalBytes: nil)])
        library.hangsAfterScript = true
        let model = ModelCatalogModel(library: library, servers: nil,
                                      traffic: .memory(granted: true))
        await model.refresh()
        model.download(model.rows[0])
        XCTAssertTrue(model.isDownloading)
        model.cancel()
        await settle(model)
        let status = model.status(for: model.rows[0])
        XCTAssertEqual(status?.stage, .stopped)
    }

    func testChipsOnlyNarrowAndSearchReachesTheSeriesAndPublisher() async {
        let (model, _) = makeModel(granted: false)
        await model.refresh()
        model.filter.search = "quiet"
        XCTAssertEqual(model.visibleRows.map(\.repoID), ["mlx-community/Small Quiet"])
        model.filter.toggle(.vision)
        XCTAssertTrue(model.visibleRows.isEmpty, "the vision chip must not keep a text-only entry")
        model.filter.clearNarrowing()
        XCTAssertEqual(model.visibleRows.count, 2)
    }

    func testATypedNameTheLibraryDoesNotCarryBecomesItsOwnCard() async {
        let (model, _) = makeModel(granted: false)
        await model.refresh()
        model.filter.search = "someone/New-Repo"
        XCTAssertEqual(model.visibleRows.last?.repoID, "someone/New-Repo")
        XCTAssertEqual(model.visibleRows.last?.origin, .custom)
        model.filter.search = "not a repository name at all"
        XCTAssertFalse(model.visibleRows.contains { $0.origin == .custom },
                       "a phone needs owner/repository; offering anything else promises a request that fails")
    }

    /// The server half of the tab is a different consequence, and it is honest about not having a server:
    /// the curated list still shows, and the button names what is missing instead of doing nothing.
    func testTheServerListShowsWithoutAServerAndRefusesToStartAPull() async {
        let (model, _) = makeModel(granted: true)
        await model.choose(.ollamaLibrary)
        XCTAssertFalse(model.rows.isEmpty)
        XCTAssertTrue(model.rows.allSatisfy { !$0.origin.landsOnThisPhone })
        model.download(model.rows[0])
        XCTAssertEqual(model.notice, "Choose a server first.")
        XCTAssertFalse(model.isDownloading)
    }
}

/// A library that answers from memory. It flips its own installed mark when a download is asked for, which
/// is what lets a test check that the view model re-reads the store instead of trusting its own memory.
@MainActor
private final class StubLibrary: LocalModelLibraryServicing {
    var rows: [LocalCatalogRow]
    var script: [LocalTransferState]
    var hangsAfterScript = false
    var downloadCalls: [String] = []

    init(rows: [LocalCatalogRow],
         script: [LocalTransferState] = [.running(doneBytes: 500, totalBytes: 1_000),
                                         .installed(bytes: 1_000)]) {
        self.rows = rows
        self.script = script
    }

    func catalogRows() async throws -> [LocalCatalogRow] { rows }
    func installedRows() async throws -> [InstalledLocalModel] { [] }

    func download(_ row: LocalCatalogRow) -> AsyncThrowingStream<LocalTransferState, any Error> {
        downloadCalls.append(row.repoID)
        rows = rows.map { $0.repoID == row.repoID ? $0.marking(installed: true) : $0 }
        // Read out to locals: the stream's build closure is `@Sendable` and non-isolated, so it may not
        // reach back through `self` for anything on this `@MainActor` stub.
        let states = script
        let hangs = hangsAfterScript
        return AsyncThrowingStream { continuation in
            for state in states { continuation.yield(state) }
            if !hangs { continuation.finish() }
        }
    }

    func delete(_ model: InstalledLocalModel) async throws {}
}
