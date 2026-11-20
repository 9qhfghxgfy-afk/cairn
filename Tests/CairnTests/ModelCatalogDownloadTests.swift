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

    /// Pause has to reach the transfer, and it must not be the path that throws bytes away. The two stop
    /// verbs share everything except what they leave behind, which is exactly the distinction a person
    /// pressing one of them is relying on.
    func testPauseStopsTheTransferAndNeverTouchesTheDiscardPath() async {
        let library = StubLibrary(rows: stubRows(),
                                  script: [.running(doneBytes: 1, totalBytes: nil)])
        library.hangsAfterScript = true
        let model = ModelCatalogModel(library: library, servers: nil,
                                      traffic: .memory(granted: true))
        await model.refresh()
        let row = model.rows[0]
        model.download(row)
        XCTAssertTrue(model.canPause(row), "a row in flight has to offer Pause")
        await model.control(.pause, for: row)
        XCTAssertEqual(library.pauseCalls, [row.repoID])
        XCTAssertTrue(library.cancelCalls.isEmpty,
                      "a pause must not reach the path that frees the bytes")
        XCTAssertEqual(model.status(for: row)?.stage, .paused)
    }

    /// Cancel is not the global Stop button: it closes the transfer *and* takes the space back, which is
    /// the half that used to be missing entirely.
    func testCancelClosesTheTransferAndFreesWhatWasFetched() async {
        let library = StubLibrary(rows: stubRows(),
                                  script: [.running(doneBytes: 1, totalBytes: nil)])
        library.hangsAfterScript = true
        let model = ModelCatalogModel(library: library, servers: nil,
                                      traffic: .memory(granted: true))
        await model.refresh()
        let row = model.rows[0]
        model.download(row)
        await model.control(.cancel, for: row)
        XCTAssertEqual(library.cancelCalls, [row.repoID],
                       "the row's Cancel must reach the transfer, not only the loop reading it")
        XCTAssertEqual(model.status(for: row)?.stage, .stopped)
        XCTAssertFalse(model.isDownloading)
        XCTAssertTrue((model.notice ?? "").contains("throws away"),
                      "the row says in the same breath what a cancel costs")
    }

    /// Bytes kept on this phone with nothing running are the state this feature exists for, and they are
    /// read from the store rather than remembered — a download iOS killed leaves nothing in memory.
    func testAKeptTransferIsOfferedAsResumeRatherThanAsAFreshDownload() async {
        let (model, library) = makeModel(granted: true)
        library.partials = ["mlx-community/Big Model"]
        await model.refresh()
        let kept = model.rows.first { $0.repoID == "mlx-community/Big Model" }!
        let other = model.rows.first { $0.repoID == "mlx-community/Small Quiet" }!
        XCTAssertTrue(model.canResume(kept), "bytes kept on this phone have to be visible")
        XCTAssertFalse(model.canResume(other))
    }

    /// The only destructive verb is the one that asks, and the question names what is lost.
    func testACancelNamesWhatItCostsAndSaysSoWhenNothingWasFetched() {
        XCTAssertTrue(ModelTransferControl.cancel.destroysProgress)
        XCTAssertFalse(ModelTransferControl.pause.destroysProgress)
        XCTAssertFalse(ModelTransferControl.resume.destroysProgress)
        let nothing = ModelTransferControl.lossLine(doneBytes: 0, totalBytes: 4_000_000_000)
        XCTAssertTrue(nothing.contains("not fetched anything"), nothing)
        let part = ModelTransferControl.lossLine(doneBytes: 1_500_000_000,
                                                 totalBytes: 4_000_000_000)
        XCTAssertTrue(part.lowercased().contains("throw"), part)
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
    /// What the transfer buttons were asked to do, recorded apart from each other: a Pause that quietly
    /// called Cancel would pass a test that only counted "stops".
    var pauseCalls: [String] = []
    var cancelCalls: [String] = []
    var discardCalls: [String] = []
    /// Repositories this stub claims to be holding kept bytes for, with nothing running.
    var partials: Set<String> = []
    var discardFailure: (any Error)?

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

    func pauseDownload(repoID: String) async { pauseCalls.append(repoID) }

    func cancelDownload(repoID: String) async throws {
        cancelCalls.append(repoID)
        partials.remove(repoID)
        if let discardFailure { throw discardFailure }
    }

    func discard(repoID: String) async throws { discardCalls.append(repoID) }

    func keepsPartialTransfer(repoID: String) async -> Bool { partials.contains(repoID) }

    func delete(_ model: InstalledLocalModel) async throws {}
}
