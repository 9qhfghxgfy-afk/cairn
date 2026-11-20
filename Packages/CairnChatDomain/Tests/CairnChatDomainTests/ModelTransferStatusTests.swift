import XCTest
@testable import CairnChatDomain

/// One progress shape for two very different transfers.
///
/// A phone transfer reports byte counts; a server pull reports a status line and whatever totals the
/// server felt like stating. The sheet draws both, so the mapping is proved here: a bar that shows 0%
/// where nothing was ever stated, or a cancelled transfer that reads as a failure, are both ways a
/// progress display lies, and neither shows up in a screenshot of a happy path.
final class ModelTransferStatusTests: XCTestCase {
    func testAPhoneTransferCarriesItsOwnWordsAndNumbers() {
        let running = ModelTransferStatus(entryID: "org/model",
                                          state: .running(doneBytes: 500, totalBytes: 1_000))
        XCTAssertEqual(running.stage, .running)
        XCTAssertEqual(running.line, "Downloading")
        XCTAssertEqual(running.fraction, 0.5)
        XCTAssertEqual(running.percentText, "50%")
        XCTAssertTrue(running.isInFlight)
        XCTAssertEqual(running.completedBytes, 500)
    }

    func testATransferWithNoStatedTotalSaysSoRatherThanDrawingZero() {
        let openEnded = ModelTransferStatus(entryID: "org/model",
                                            state: .running(doneBytes: 700, totalBytes: nil))
        XCTAssertNil(openEnded.fraction)
        XCTAssertEqual(openEnded.percentText, "not stated")
        XCTAssertEqual(openEnded.completedBytes, 700, "bytes fetched are still a fact")
        XCTAssertTrue(openEnded.isInFlight)
    }

    func testEveryStageReadsAsItReallyIs() {
        XCTAssertEqual(ModelTransferStatus(entryID: "m", state: .queued).stage, .queued)
        XCTAssertEqual(ModelTransferStatus(entryID: "m", state: .verifying).line,
                       "Checking the checksum")
        let landed = ModelTransferStatus(entryID: "m", state: .installed(bytes: 8))
        XCTAssertEqual(landed.stage, .finished)
        XCTAssertFalse(landed.isInFlight)
        XCTAssertEqual(landed.completedBytes, 8)
        XCTAssertEqual(ModelTransferStatus(entryID: "m", state: .stopped).line, "Stopped")
        // A failure keeps the store's own message; "the checksum did not match" and "the download
        // failed" are not the same fact to show a person.
        XCTAssertEqual(ModelTransferStatus(entryID: "m",
                                           state: .failed("checksum mismatch")).line,
                       "checksum mismatch")
        XCTAssertFalse(ModelTransferStatus(entryID: "m", state: .failed("x")).isInFlight)
    }

    func testAServerPullIsShownInItsOwnWordsAndNeverRewritten() {
        let pull = ModelTransferStatus(
            entryID: "qwen3:4b",
            pull: ModelPullProgress(modelName: "qwen3:4b", statusText: "pulling manifest")
        )
        XCTAssertEqual(pull.line, "pulling manifest")
        XCTAssertNil(pull.fraction)
        XCTAssertEqual(pull.percentText, "not stated")
        XCTAssertEqual(pull.entryID, "qwen3:4b")

        let sized = ModelTransferStatus(
            entryID: "qwen3:4b",
            pull: ModelPullProgress(modelName: "qwen3:4b", statusText: "downloading",
                                    completedBytes: 1, totalBytes: 3)
        )
        XCTAssertEqual(sized.percentText, "33%")
    }

    /// The line the sheet actually draws: the stage and the file it is sitting on, joined.
    ///
    /// A four-file repository whose bar says only "Downloading" cannot be read — the person cannot tell
    /// whether it is on file one of four or file four of four. The join lives in the domain so the sheet
    /// cannot invent a filename it was never handed: a server pull and a failure carry none, and both have
    /// to read as the line they were given and nothing more.
    func testTheDrawnLineNamesTheFileInTheHandAndNothingElse() {
        XCTAssertEqual(ModelTransferStatus(entryID: "m",
                                           state: .running(doneBytes: 1, totalBytes: 4,
                                                           file: "model-00002-of-00004.safetensors")).stageDetail,
                       "Downloading · model-00002-of-00004.safetensors")
        XCTAssertEqual(ModelTransferStatus(entryID: "m",
                                           state: .paused(doneBytes: 1, totalBytes: 4,
                                                          file: "model.safetensors")).stageDetail,
                       "Paused · model.safetensors")
        // Nothing named, nothing appended — the line stands alone rather than trailing a separator.
        XCTAssertEqual(ModelTransferStatus(entryID: "m",
                                           state: .running(doneBytes: 1, totalBytes: 4)).stageDetail,
                       "Downloading")
        XCTAssertEqual(ModelTransferStatus(entryID: "m",
                                           state: .running(doneBytes: 1, totalBytes: 4, file: "")).stageDetail,
                       "Downloading")
        // A refusal carries no file, so its message is shown whole and unadorned.
        XCTAssertEqual(ModelTransferStatus(entryID: "m",
                                           state: .failed("The Hub has no file at that address (status 404).")).stageDetail,
                       "The Hub has no file at that address (status 404).")
        XCTAssertEqual(ModelTransferStatus(entryID: "m",
                                           state: .installed(bytes: 8)).stageDetail,
                       "Installed on this phone")
        // A server pull is the server's sentence, never Cairn's guess about another machine's file.
        XCTAssertEqual(ModelTransferStatus(entryID: "m",
                                           pull: ModelPullProgress(modelName: "m",
                                                                   statusText: "pulling manifest")).stageDetail,
                       "pulling manifest")
    }

    /// A sheet must never show one model's numbers under another model's name.
    func testAStatusAlwaysNamesTheEntryItBelongsTo() {
        XCTAssertEqual(ModelTransferStatus(entryID: "a", state: .queued).entryID, "a")
        XCTAssertEqual(ModelTransferStatus(entryID: "b",
                                           pull: ModelPullProgress(modelName: "b",
                                                                   statusText: "starting")).entryID, "b")
    }
}
