import XCTest
@testable import CairnChatDomain

/// What a file may be attached, and what is said when it may not.
///
/// The property these tests exist to protect: Cairn never invents the contents of a file it could not
/// read. Every refusal here is a refusal to guess, and a refusal that quotes the file's contents would be
/// its own leak, so the messages are checked for that too.
final class AttachmentAcceptanceTests: XCTestCase {

    func testAnEmptyFileHasNothingToAttach() {
        XCTAssertEqual(
            AttachmentCeilings.rejection(kind: .document, byteCount: 0), .nothingToRead
        )
        XCTAssertEqual(
            AttachmentCeilings.rejection(kind: .image, byteCount: -1), .nothingToRead
        )
    }

    func testOversizedFilesAreRefusedAndFilesAtTheCeilingAreNot() {
        // The ceilings bound one read into memory. They are not a count of files, so the tests below
        // assert the boundary rather than an allowance.
        XCTAssertEqual(
            AttachmentCeilings.rejection(kind: .image, byteCount: AttachmentCeilings.imageByteCount),
            nil
        )
        XCTAssertEqual(
            AttachmentCeilings.rejection(
                kind: .image, byteCount: AttachmentCeilings.imageByteCount + 1
            ),
            .tooLargeToHold
        )
        XCTAssertEqual(
            AttachmentCeilings.rejection(
                kind: .document, byteCount: AttachmentCeilings.documentByteCount + 1
            ),
            .tooLargeToHold
        )
    }

    func testABinaryContainerIsRefusedRatherThanReadAsText() {
        var bytes = Data("JFIF".utf8)
        bytes.append(0)
        bytes.append(Data("and some bytes after the marker".utf8))
        let read = DocumentTextExtractor.extract(name: "photo.jpg", bytes: bytes)
        XCTAssertEqual(read.rejected, .notPlainText)
        XCTAssertTrue(read.text.isEmpty, "a refused file must not yield text to search")
    }

    func testTextWithOneStrayControlByteDeepInsideIsStillText() {
        var bytes = Data(String(repeating: "a sentence of prose. ", count: 400).utf8)
        bytes.append(0x01)
        bytes.append(Data("trailing prose".utf8))
        XCTAssertFalse(DocumentTextExtractor.looksBinary(bytes))
        XCTAssertNil(DocumentTextExtractor.extract(name: "notes.txt", bytes: bytes).rejected)
    }

    func testTextThatIsNotUTF8IsRefusedRatherThanGuessedAt() {
        let notUTF8 = Data([0x41, 0xC3, 0x28, 0xA0, 0xFF])
        let read = DocumentTextExtractor.extract(name: "legacy.txt", bytes: notUTF8)
        XCTAssertEqual(read.rejected, .notUTF8Text)
        XCTAssertTrue(read.text.isEmpty)
    }

    func testWindowsLineEndingsBecomeOneKindOfNewline() {
        let read = DocumentTextExtractor.extract(name: "cr.txt", bytes: Data("a\r\nb\rc\n".utf8))
        XCTAssertEqual(read.text, "a\nb\nc\n")
    }

    func testATailCutOffIsRecordedRatherThanPresentedAsTheWholeFile() {
        let long = String(repeating: "word ", count: AttachmentCeilings.extractedCharacterCount)
        let read = DocumentTextExtractor.extract(name: "big.txt", bytes: Data(long.utf8))
        XCTAssertTrue(read.truncated)
        XCTAssertEqual(read.text.count, AttachmentCeilings.extractedCharacterCount)
        let note = DocumentTextExtractor.truncationNote("big.txt")
        XCTAssertTrue(note.contains("big.txt"))
        XCTAssertTrue(note.contains("\(AttachmentCeilings.extractedCharacterCount)"))
    }

    func testARefusalNamesTheFileAndNeverQuotesInsideIt() {
        let secret = "the part of the file nobody was meant to see"
        var bytes = Data(secret.utf8)
        bytes.append(0)
        let read = DocumentTextExtractor.extract(name: "private.bin", bytes: bytes)
        let message = read.rejected?.message ?? ""
        XCTAssertTrue(message.contains("private.bin") || message.contains("file"))
        XCTAssertFalse(message.contains(secret), "a refusal must not repeat what it refused to read")
    }
}
