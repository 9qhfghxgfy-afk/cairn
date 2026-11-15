import XCTest
@testable import CairnChatDomain

final class LineStreamParserTests: XCTestCase {

    func testCompleteLinesInOneChunk() {
        var parser = LineStreamParser()
        let lines = parser.feed(Data("alpha\nbravo\ncharlie\n".utf8))
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(LineStreamParser.decode(lines[0]), "alpha")
        XCTAssertEqual(LineStreamParser.decode(lines[2]), "charlie")
        XCTAssertEqual(parser.pendingByteCount, 0)
    }

    func testPartialLineWaitsForMoreBytes() {
        var parser = LineStreamParser()
        XCTAssertEqual(parser.feed(Data("first line without newline".utf8)).count, 0)
        XCTAssertEqual(parser.pendingByteCount, "first line without newline".count)
        let done = parser.feed(Data(" continues\n".utf8))
        XCTAssertEqual(done.count, 1)
        XCTAssertEqual(LineStreamParser.decode(done[0]),
                       "first line without newline continues")
    }

    func testCRLFTerminatedLines() {
        var parser = LineStreamParser()
        let lines = parser.feed(Data("data: one\r\ndata: two\r\n".utf8))
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(LineStreamParser.decode(lines[0]), "data: one")
        XCTAssertEqual(LineStreamParser.decode(lines[1]), "data: two")
    }

    /// The whole point of splitting bytes before decoding: a chunk may end in
    /// the middle of a multibyte UTF-8 sequence and the line must still decode.
    func testByteByByteFeedKeepsMultibyteIntact() {
        let payload = Data("héllo ✅ ok\n".utf8)
        var parser = LineStreamParser()
        var collected: [Data] = []
        for byte in payload {
            collected.append(contentsOf: parser.feed(Data([byte])))
        }
        XCTAssertEqual(collected.count, 1)
        XCTAssertEqual(LineStreamParser.decode(collected[0]), "héllo ✅ ok")
    }

    func testTrailingPartialLineIsRecoverable() {
        var parser = LineStreamParser()
        _ = parser.feed(Data("complete\ntail-without-newline".utf8))
        let tail = parser.takeTrailingPartialLine()
        XCTAssertEqual(tail, Data("tail-without-newline".utf8))
        XCTAssertNil(parser.takeTrailingPartialLine())
    }

    func testDecodeRejectsInvalidUTF8() {
        XCTAssertNil(LineStreamParser.decode(Data([0xFF, 0xFE])))
    }
}