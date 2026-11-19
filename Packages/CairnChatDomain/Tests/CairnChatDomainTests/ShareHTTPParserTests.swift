import XCTest
@testable import CairnChatDomain

/// The request reader. Everything the socket hands over is untrusted bytes, so this is where a
/// hostile or half-written request has to stop rather than reach a route.
final class ShareHTTPParserTests: XCTestCase {

    private func bytes(_ text: String) -> Data { Data(text.utf8) }

    func testAWholeGetRequestParsesWithItsHeaders() {
        let raw = "GET /api/tags HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer abc123\r\n\r\n"
        guard case .complete(let request) = ShareHTTPParser.parse(bytes(raw)) else {
            return XCTFail("a whole request parses")
        }
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.path, "/api/tags")
        XCTAssertEqual(request.header("authorization"), "Bearer abc123")
        XCTAssertEqual(request.header("AUTHORIZATION"), "Bearer abc123", "header names are read case-insensitively")
        XCTAssertEqual(request.endpoint, .modelList(dialect: .ollama))
        XCTAssertTrue(request.body.isEmpty)
    }

    func testAQueryIsSplitOffThePath() {
        let raw = "GET /v1/models?limit=5 HTTP/1.1\r\n\r\n"
        guard case .complete(let request) = ShareHTTPParser.parse(bytes(raw)) else {
            return XCTFail("a request with no headers parses")
        }
        XCTAssertEqual(request.path, "/v1/models")
        XCTAssertEqual(request.query, "limit=5")
        XCTAssertEqual(request.endpoint, .modelList(dialect: .openAI))
    }

    func testALenientLineEndingStillParses() {
        let raw = "POST /api/chat HTTP/1.1\nContent-Length: 5\n\nhello"
        guard case .complete(let request) = ShareHTTPParser.parse(bytes(raw)) else {
            return XCTFail("a client that sends bare newlines is still a client")
        }
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(String(data: request.body, encoding: .utf8), "hello")
    }

    /// A request that has not fully arrived is the normal case mid-read, not an error — and a
    /// body shorter than its own Content-Length must not be answered as if it were whole.
    func testAPartialRequestAsksForMoreBytesInsteadOfAnswering() {
        guard case .needMoreBytes = ShareHTTPParser.parse(bytes("GET /api/vers")) else {
            return XCTFail("no terminator yet")
        }
        guard case .needMoreBytes = ShareHTTPParser.parse(bytes("POST /api/chat HTTP/1.1\r\nContent-Length: 20\r\n\r\nshort")) else {
            return XCTFail("the body has not arrived")
        }
        guard case .complete(let request) = ShareHTTPParser.parse(bytes("POST /api/chat HTTP/1.1\r\nContent-Length: 5\r\n\r\nhelloEXTRA")) else {
            return XCTFail("the declared body has arrived")
        }
        XCTAssertEqual(request.body.count, 5, "only the declared body is taken")
    }

    func testGarbageIsRefusedWithATypedReason() {
        for raw in ["\r\n\r\n", "NOTAREQUEST\r\n\r\n", "GET nota-path HTTP/1.1\r\n\r\n", "GET /api/tags HTTP/2.0\r\n\r\n"] {
            guard case .rejected(let failure) = ShareHTTPParser.parse(bytes(raw)) else {
                return XCTFail("garbage must be refused")
            }
            XCTAssertTrue([ShareParseFailure.malformedRequest, .unsupportedVersion].contains(failure), "\(raw)")
        }
    }

    func testOversizedHeadersAndBodiesAreRefusedRatherThanHeld() {
        let bigHeaders = "GET /api/tags HTTP/1.1\r\n" + String(repeating: "X-Big: \(String(repeating: "a", count: 200))\r\n", count: 120) + "\r\n"
        guard case .rejected(.headersTooLarge) = ShareHTTPParser.parse(bytes(bigHeaders)) else {
            return XCTFail("headers past the budget are refused")
        }
        let declared = "POST /api/chat HTTP/1.1\r\nContent-Length: \(ShareHTTPParser.bodyByteBudget + 1)\r\n\r\n"
        guard case .rejected(.bodyTooLarge) = ShareHTTPParser.parse(bytes(declared)) else {
            return XCTFail("a body past the budget is refused before it is read")
        }
        // Chunked bodies are not read at all: guessing where one ends is how a request smearing
        // into the next one on a kept-alive socket happens.
        guard case .rejected(.unsupportedBodyEncoding) = ShareHTTPParser.parse(bytes("POST /api/chat HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n")) else {
            return XCTFail("a chunked body is refused, not guessed")
        }
    }

    /// **This is the shape every real client sends.** CR+LF is one `Character` in Swift, so a head
    /// split on characters keeps its lines glued together: the request line comes back as one long
    /// line, it splits into more than three fields, and the request is refused as malformed. The
    /// head is split on the LF byte instead, and this test is what fails if that is ever undone.
    func testARequestWithSeveralCRLFHeaderLinesKeepsEveryLine() {
        let raw = "POST /v1/chat/completions HTTP/1.1\r\nHost: 192.168.1.20:11434\r\n"
            + "Authorization: Bearer 0123456789abcdef0123456789abcdef\r\n"
            + "Content-Type: application/json\r\nContent-Length: 13\r\n\r\n{\"model\":\"m\"}"
        guard case .complete(let request) = ShareHTTPParser.parse(bytes(raw)) else {
            return XCTFail("a CRLF request with headers is the normal case, not a malformed one")
        }
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/v1/chat/completions")
        XCTAssertEqual(request.endpoint, .chat(dialect: .openAI))
        XCTAssertEqual(request.header("host"), "192.168.1.20:11434")
        XCTAssertEqual(request.header("content-type"), "application/json")
        XCTAssertEqual(ShareAuthChallenge.presentedToken(in: request), "0123456789abcdef0123456789abcdef")
        XCTAssertEqual(request.body, bytes("{\"model\":\"m\"}"), "only the declared body is taken")
    }
}
