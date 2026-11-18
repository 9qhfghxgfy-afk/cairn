import XCTest
@testable import CairnChatDomain

/// Cutting a document into retrieval-sized pieces.
///
/// Two properties hold and both are asserted here: the same text always cuts the same way — a citation
/// written today has to point at the same place after a relaunch — and no character of the document is
/// left out of every chunk, because a passage that is unreachable is a document that partly does not
/// exist.
final class DocumentChunkerTests: XCTestCase {
    private let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    func testAnEmptyDocumentCutsToNoChunks() {
        XCTAssertTrue(
            DocumentChunker.chunks("", documentID: id, documentName: "empty.txt").isEmpty
        )
    }

    func testASmallDocumentStaysOneWholeChunk() {
        let text = "A short note about the wiring in the garage."
        let chunks = DocumentChunker.chunks(text, documentID: id, documentName: "note.txt")
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks.first?.text, text)
        XCTAssertEqual(chunks.first?.startCharacter, 0)
        XCTAssertEqual(chunks.first?.index, 0)
    }

    func testTheSameTextAlwaysCutsInTheSamePlaces() {
        let text = String(repeating: "Sentence about pumps and pressure. \n", count: 200)
        let first = DocumentChunker.chunks(text, documentID: id, documentName: "pump.txt")
        let second = DocumentChunker.chunks(text, documentID: id, documentName: "pump.txt")
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.map(\.id), first.map { "\(id.uuidString)#\($0.index)" })
    }

    func testEveryCharacterOfTheDocumentAppearsInAtLeastOneChunk() {
        let text = (1...4_000).map { "line \($0) of the manual describes one part\n" }.joined()
        let characters = Array(text)
        let chunks = DocumentChunker.chunks(text, documentID: id, documentName: "manual.txt")
        XCTAssertGreaterThan(chunks.count, 2)
        var covered = [Bool](repeating: false, count: characters.count)
        for chunk in chunks {
            let start = chunk.startCharacter
            let end = start + Array(chunk.text).count
            XCTAssertLessThanOrEqual(end, characters.count)
            for offset in start..<end { covered[offset] = true }
        }
        XCTAssertFalse(covered.contains(false), "a character in no chunk can never be cited")
    }

    func testChunksAdvanceAndOverlapByAtMostAQuarterOfAChunk() {
        let text = String(repeating: "clause, ", count: 2_000)
        let chunks = DocumentChunker.chunks(
            text, documentID: id, documentName: "long.txt", characterCount: 400, overlap: 200
        )
        XCTAssertGreaterThan(chunks.count, 5)
        for pair in zip(chunks, chunks.dropFirst()) {
            XCTAssertGreaterThan(pair.1.startCharacter, pair.0.startCharacter)
            let overlap = (pair.0.startCharacter + pair.0.text.count) - pair.1.startCharacter
            XCTAssertGreaterThanOrEqual(overlap, 0)
            // 400/4 is the most a chunk may repeat, however the caller asked for overlap.
            XCTAssertLessThanOrEqual(overlap, 100)
        }
    }

    func testACutLandsOnABoundarySoAPassageDoesNotStartMidWord() {
        let text = String(repeating: "pump pressure valve gauge ", count: 600)
        let characters = Array(text)
        let chunks = DocumentChunker.chunks(
            text, documentID: id, documentName: "words.txt", characterCount: 400, overlap: 0
        )
        XCTAssertGreaterThan(chunks.count, 3)
        for chunk in chunks.dropLast() {
            let cut = chunk.startCharacter + Array(chunk.text).count
            XCTAssertLessThan(cut, characters.count)
            XCTAssertTrue(
                characters[cut - 1] == " " || characters[cut - 1] == "\n",
                "a cut mid-word leaves a half word at the end of a cited passage"
            )
        }
    }

    func testALineEndIsPreferredOverASpaceWhenBothAreInRange() {
        let text = String(repeating: "row of text that runs long enough to be cut\n", count: 200)
        let chunks = DocumentChunker.chunks(
            text, documentID: id, documentName: "rows.txt", characterCount: 600, overlap: 0
        )
        XCTAssertGreaterThan(chunks.count, 2)
        XCTAssertTrue(
            chunks.dropLast().allSatisfy { $0.text.hasSuffix("\n") },
            "a chunk should end at a line end when one is near the cut"
        )
    }
}
