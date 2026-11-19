import XCTest
@testable import CairnChatDomain

/// The head this server writes, and the error shapes it writes them in. A stream with a
/// `Content-Length` is a stream no client can end, so these are wire rules rather than style.
final class ShareReplyTests: XCTestCase {

    func testAWholeAnswerDeclaresItsLengthAndNamesCairnAsTheServer() {
        let reply = ShareHTTPResponse.json(status: 200, body: ShareOllamaEncoder.versionBody())
        let head = reply.headText
        XCTAssertTrue(head.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(head.contains("Server: \(ShareHTTPResponse.serverName)"))
        XCTAssertTrue(head.contains("Content-Length: \(reply.bodyData.count)"))
        XCTAssertTrue(ShareHTTPResponse.serverName.hasPrefix("Cairn"), "a client must be able to tell it reached a phone running Cairn")
        XCTAssertTrue(head.hasSuffix("\r\n\r\n"))
        XCTAssertEqual(reply.allBytes, head.data + reply.bodyData)
    }

    /// A stream gets no length and `Connection: close`: the end of the answer is the end of the
    /// socket, which is what lets a frame go out the moment it is produced.
    func testAStreamDeclaresNoLengthAndNoBuffering() {
        let head = ShareHTTPResponse.streaming(dialect: .openAI).headText
        XCTAssertFalse(head.contains("Content-Length"))
        XCTAssertTrue(head.contains("Connection: close"))
        XCTAssertTrue(head.contains("Content-Type: text/event-stream"))
        XCTAssertTrue(head.contains("X-Accel-Buffering: no"))
        XCTAssertTrue(ShareHTTPResponse.streaming(dialect: .ollama).headText.contains("application/x-ndjson"))
        XCTAssertTrue(ShareHTTPResponse.streaming(dialect: .openAI).headText.contains("Cache-Control: no-store"))
    }

    /// An error in the wrong shape reads to a strict client as a server that answered nothing.
    func testEachDialectGetsItsOwnErrorShape() throws {
        let ollama = ShareHTTPResponse.error(status: 401, dialect: .ollama, message: "a key is needed")
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: ollama.bodyData).dictionaryValue?["error"]?.textValue,
                       "a key is needed")
        let openAI = ShareHTTPResponse.error(status: 401, dialect: .openAI, message: "a key is needed")
        let inner = try JSONDecoder().decode(JSONValue.self, from: openAI.bodyData).dictionaryValue?["error"]?.dictionaryValue
        XCTAssertEqual(inner?["message"]?.textValue, "a key is needed")
        XCTAssertEqual(inner?["type"]?.textValue, "authentication_error")
        XCTAssertTrue(ollama.headText.hasPrefix("HTTP/1.1 401 Unauthorized"))
        XCTAssertEqual(ShareHTTPResponse.kind(for: 404), "not_found_error")
        XCTAssertEqual(ShareHTTPResponse.kind(for: 400), "invalid_request_error")
        XCTAssertEqual(ShareHTTPResponse.kind(for: 500), "server_error")
    }

    /// A browser preflight carries no turn and no key, so it is answered with the permission and
    /// stops there — and the origin is echoed rather than widened to a wildcard.
    func testAPreflightIsAnsweredAndStopsThere() {
        let reply = ShareHTTPResponse.preflight(origin: "http://localhost:3000")
        XCTAssertEqual(reply.status, 204)
        XCTAssertNil(reply.contentType)
        XCTAssertTrue(reply.headText.contains("Access-Control-Allow-Origin: http://localhost:3000"))
        XCTAssertTrue(reply.headText.contains("Authorization, X-API-Key"))
        XCTAssertTrue(reply.bodyData.isEmpty)
        XCTAssertFalse(ShareHTTPResponse.preflight(origin: nil).headText.contains("Access-Control-Allow-Origin"))
    }

    func testAFramesBodyIsTheFramesInOrder() {
        let reply = ShareHTTPResponse.streaming(
            dialect: .ollama,
            frames: [ShareFrame.ndjson(ShareOllamaEncoder.contentFrame(model: "m", createdAt: "t", text: "Hi")),
                     ShareFrame.ndjson(ShareOllamaEncoder.finalFrame(model: "m", createdAt: "t", reason: .stop, evalCount: 1, evalDurationMicros: 1, promptEvalCount: nil))]
        )
        let body = String(data: reply.bodyData, encoding: .utf8) ?? ""
        XCTAssertTrue(body.hasSuffix("\n"))
        XCTAssertEqual(body.filter { $0 == "\n" }.count, 2, "one object per line, nothing between them")
        XCTAssertTrue(reply.streaming)
    }

    func testAStatusWithoutAKnownReasonStillWritesALegalHead() {
        XCTAssertTrue(ShareHTTPResponse.json(status: 418, body: "").headText.contains("HTTP/1.1 418"))
        XCTAssertEqual(ShareHTTPResponse.reason(for: 413), "Content Too Large")
    }
}

private extension String {
    var data: Data { Data(utf8) }
}
