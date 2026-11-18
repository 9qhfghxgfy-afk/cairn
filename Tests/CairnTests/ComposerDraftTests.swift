import CairnChatDomain
import XCTest

/// The composer's rules about a file, tested against the object that owns them.
///
/// A user picks a file and the composer either takes it or says why not — before anything is written, before
/// anything is sent, and in words the user can act on. Each rule here exists because the alternative is found
/// out later: a document accepted as bytes alone sends no text, so the model answers from nothing and sounds
/// sure doing it; a photo quietly shrunk loses the street sign the user was asking about; a temporary chat
/// that drops the file when the app closes reads as a broken app rather than as the promise that chat makes.
///
/// The preparer is injected, so the three halves of the picture are each tested where they live: the domain's
/// arithmetic (`ImagePreparationPolicy`, `AttachmentCeilings`) on a host, the codec (`ImageIOPreparer`) on a
/// simulator against real bytes, and here the two things only the composer decides — that a refusal reaches the
/// user as the preparer's own sentence, and that an accepted file is what the preparer produced rather than
/// what was handed in.
@MainActor
final class ComposerDraftTests: XCTestCase {
    /// A preparer with a chosen answer, because the alternative is testing this file against the real codec —
    /// which needs a simulator, real bytes, and no way to ask "what if the codec said no".
    private struct StubPreparer: ImagePreparing {
        let outcome: Result<PreparedImage, AttachmentRejection>
        func prepare(_ data: Data, name: String) -> Result<PreparedImage, AttachmentRejection> { outcome }
    }

    private func draft(refusing reason: AttachmentRejection) -> ComposerDraft {
        ComposerDraft(preparer: StubPreparer(outcome: .failure(reason)))
    }

    func testAnEmptyDraftHasNothingToShowAndSaysNothingAboutFiles() {
        let subject = ComposerDraft()
        XCTAssertTrue(subject.isEmpty)
        XCTAssertNil(subject.refusal)
        XCTAssertTrue(subject.attachments.isEmpty)
        XCTAssertEqual(subject.imageCount, 0)
        XCTAssertNil(subject.visionWarning(in: nil), "no chat means no engine to warn about")
    }

    func testAPlainTextFileIsReadOnThisDeviceAndStagedWithTheTextItYielded() {
        let text = "The north face holds snow longer than the south face."
        var subject = ComposerDraft()
        subject.accept(documentBytes: Data(text.utf8), name: "notes.txt")

        let staged = subject.staged.first
        XCTAssertNil(subject.refusal)
        XCTAssertEqual(staged?.kind, .document)
        XCTAssertEqual(staged?.name, "notes.txt")
        XCTAssertEqual(staged?.text, text, "retrieval reads stored text, so the reading cannot be deferred")
        XCTAssertTrue(staged?.hasText ?? false)
        XCTAssertTrue(staged?.summary.contains("document") ?? false, "a chip says what kind of thing it is")
        XCTAssertFalse(subject.isEmpty)
    }

    func testAFileThatIsNotPlainTextIsRefusedAndNothingIsStaged() {
        // A real PDF's opening bytes. The refusal is the feature: Cairn reads plain text on the phone and will
        // not guess at what a container holds, so a contract that arrives as a PDF is named rather than stored.
        var subject = ComposerDraft()
        subject.accept(documentBytes: Data("%PDF-1.5\n".utf8) + Data([0x00, 0x01, 0x02, 0x00]),
                       name: "contract.pdf")

        XCTAssertEqual(subject.refusal, AttachmentRejection.notPlainText.message)
        XCTAssertTrue(subject.isEmpty, "a document with no text must not reach the turn as half a turn")
    }

    func testAFileTooBigToFitIsRefusedBeforeItsBytesAreLookedAt() {
        var subject = ComposerDraft()
        subject.accept(documentBytes: Data(count: AttachmentCeilings.documentByteCount + 1), name: "huge.txt")
        XCTAssertTrue(subject.refusal?.contains("smaller file") ?? false, "\(subject.refusal ?? "<nil>")")
        XCTAssertTrue(subject.isEmpty)

        // A photo over its own ceiling gets the same sentence, because the user's fix is the same one.
        var pictures = ComposerDraft()
        pictures.accept(imageBytes: Data(count: AttachmentCeilings.imageByteCount + 1), name: "Panorama")
        XCTAssertEqual(pictures.refusal, AttachmentRejection.tooLargeToHold.message)
        XCTAssertTrue(pictures.isEmpty)
    }

    func testThePictureStagedIsTheOneThePreparerProduced() {
        // A resampled photo arrives with a new name as well as new bytes: a HEIC that is now JPEG has to stop
        // claiming to be HEIC, or the chip states something about the file that is no longer true.
        let shrunk = PreparedImage(
            data: Data([0xFF, 0xD8, 0x01]), name: "IMG_0042.jpg", declaredType: "public.jpeg"
        )
        var subject = ComposerDraft(preparer: StubPreparer(outcome: .success(shrunk)))
        subject.accept(imageBytes: Data(count: 4000), name: "IMG_0042.heic")

        XCTAssertNil(subject.refusal)
        XCTAssertEqual(subject.staged.first?.payload, shrunk.data, "the turn sends what was actually kept")
        XCTAssertEqual(subject.staged.first?.name, "IMG_0042.jpg")
        XCTAssertEqual(subject.staged.first?.byteCount, shrunk.data.count)
        XCTAssertEqual(subject.imageCount, 1)
    }

    func testAPictureTheCodecCannotReadIsRefusedInTheCodecsOwnWords() {
        var subject = draft(refusing: .unreadableImage)
        subject.accept(imageBytes: Data("not a photograph".utf8), name: "photo.jpg")

        // The composer invents no diagnosis of its own; it passes on the sentence that names the real reason,
        // which is the difference between "share a smaller file" and "that was never an image".
        XCTAssertEqual(subject.refusal, AttachmentRejection.unreadableImage.message)
        XCTAssertTrue(subject.isEmpty)
    }

    func testTextThatIsNotUTF8IsRefusedRatherThanGuessedAt() {
        var subject = ComposerDraft()
        subject.accept(documentBytes: Data([0xC3, 0x28, 0xA0, 0xFF]), name: "old-notes.txt")

        XCTAssertEqual(subject.refusal, AttachmentRejection.notUTF8Text.message)
        XCTAssertTrue(subject.isEmpty, "a wrong decoding is worse than no decoding")
    }

    func testAGoodPickClearsTheSentenceAboutTheBadOne() {
        var subject = ComposerDraft()
        subject.accept(documentBytes: Data("%PDF-1.5".utf8) + Data([0x00]), name: "contract.pdf")
        XCTAssertNotNil(subject.refusal)

        subject.accept(documentBytes: Data("notes".utf8), name: "notes.txt")
        XCTAssertNil(subject.refusal, "the line is about the last pick, not a verdict on the conversation")
        XCTAssertEqual(subject.staged.count, 1)
    }

    func testRemovingOneFileLeavesTheOthersAloneAndInTheirOriginalOrder() throws {
        var subject = ComposerDraft()
        subject.accept(documentBytes: Data("one".utf8), name: "first.txt")
        subject.accept(documentBytes: Data("two".utf8), name: "second.txt")
        subject.accept(imageBytes: Data([0xFF, 0xD8]), name: "Photo 1")
        let first = try XCTUnwrap(subject.staged.first)
        XCTAssertEqual(subject.staged.count, 3)

        subject.remove(first.id)
        XCTAssertEqual(subject.staged.map(\.name), ["second.txt", "Photo 1"])
        XCTAssertEqual(subject.staged.first?.name, "second.txt", "the chips do not shuffle under the user's hand")
    }

    func testClearingTheDraftTakesTheRefusalWithTheFiles() {
        var subject = draft(refusing: .notPlainText)
        subject.accept(documentBytes: Data("anything".utf8), name: "notes.txt")
        XCTAssertNotNil(subject.refusal)

        subject.clear()
        XCTAssertTrue(subject.isEmpty)
        XCTAssertNil(subject.refusal, "a cleared composer must not go on saying no about a file that is gone")
    }

    func testTheLineAboutWhereFilesLiveNamesTheReasonThatActuallyApplies() {
        let subject = ComposerDraft()
        XCTAssertEqual(
            subject.storageNotice(temporaryChat: true, storageAvailable: true),
            AttachmentNotices.temporaryChatNotice
        )
        XCTAssertEqual(
            subject.storageNotice(temporaryChat: false, storageAvailable: false),
            AttachmentNotices.storageUnavailableNotice
        )
        XCTAssertNil(subject.storageNotice(temporaryChat: false, storageAvailable: true))
        XCTAssertNotNil(
            subject.storageNotice(temporaryChat: true, storageAvailable: false),
            "a temporary chat with nowhere to write says the promise that binds first"
        )
    }
}

