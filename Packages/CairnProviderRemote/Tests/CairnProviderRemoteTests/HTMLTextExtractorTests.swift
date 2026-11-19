import Foundation
import XCTest
import CairnChatDomain
@testable import CairnProviderRemote

/// P3b readability and bounds: what a fetched page becomes before a model reads it, and how far
/// a body is allowed to arrive. Page furniture that survives becomes a claim about the page that the
/// page never made, and a body read past its cap is a download the tool had already refused.
final class HTMLTextExtractorTests: XCTestCase {

    private func call(_ url: String) -> ToolCall {
        ToolCall(id: "call-1", name: BuiltInTool.webFetch, arguments: ["url": .text(url)])
    }

    private let turn = ToolExecutionContext(toolsEnabled: true, outboundWebAllowed: true)

    /// The bound travels with the request instead of being applied to a body already read in full, and
    /// the real delegate stops one byte past it. "Too large" is reported as the reason, because
    /// "cancelled" would make it look as though the user had stopped the turn.
    func testTheByteBoundIsCarriedWithTheRequestAndEnforcedAsBytesArrive() async throws {
        let transport = RecordingWebTransport(reply: .html("<html><body>small</body></html>"))
        let outcome = try await openFetchTool(transport, byteLimit: 4096)
            .execute(call("https://example.com/page"), context: turn)
        XCTAssertTrue(outcome.succeeded)
        XCTAssertEqual(transport.byteLimits, [4096], "the tool's own bound is what the transport caps at")

        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: try XCTUnwrap(URL(string: "https://example.com")))
        let delegate = WebLoadDelegate(byteLimit: 8, redirectLimit: 0, redirectAllowed: { _ in false })
        do {
            let answer = try await withCheckedThrowingContinuation {
                (sink: CheckedContinuation<WebHTTPResponse, any Error>) in
                delegate.bind(sink)
                delegate.urlSession(session, dataTask: task, didReceive: Data("1234".utf8))
                delegate.urlSession(session, dataTask: task, didReceive: Data("56789".utf8))
                delegate.urlSession(session, task: task, didCompleteWithError: nil)
            }
            XCTFail("the cap should have bitten, got status \(answer.status)")
        } catch let failure as ToolFailure {
            XCTAssertEqual(failure.error, .responseTooLarge)
        }

        let fits = WebLoadDelegate(byteLimit: 16, redirectLimit: 0, redirectAllowed: { _ in false })
        let body = try await withCheckedThrowingContinuation {
            (sink: CheckedContinuation<WebHTTPResponse, any Error>) in
            fits.bind(sink)
            fits.urlSession(session, dataTask: task, didReceive: Data("12345678".utf8))
            fits.urlSession(session, task: task, didCompleteWithError: nil)
        }
        XCTAssertEqual(String(data: body.data, encoding: .utf8), "12345678", "under the cap, whole")
        session.invalidateAndCancel()
    }

    /// Page furniture out, prose in: navigation, script, style and asides are skipped whole rather than
    /// stripped after the fact, and the page's own `main` is read as the article. A body that is not
    /// text at all yields nothing, because a wall of replacement characters is something a model would
    /// summarise into a claim the file never made.
    func testAPageIsReadAsItsProseWithTheFurnitureRemoved() throws {
        let page = "<html><head><style>.x{color:red}</style><title>Site</title></head><body>"
            + "<nav><a href=\"/\">Home</a></nav><script>var tracking = 1;</script>"
            + "<aside>Subscribe to the newsletter</aside>"
            + "<main><h1>Rain in Paris</h1><p>The city was &mdash; wet &amp; grey.</p></main>"
            + "<footer>Copyright</footer></body></html>"
        let text = WebFetchTool.readableText(in: .html(page))
        XCTAssertTrue(text.contains("Rain in Paris"))
        XCTAssertTrue(text.contains("The city was — wet & grey."), "entities decoded, words left as written")
        XCTAssertFalse(text.contains("tracking"), "a script is not prose")
        XCTAssertFalse(text.contains("Subscribe"), "an aside is not the article")
        XCTAssertFalse(text.contains("color:red"), "a stylesheet is not the page")
        XCTAssertFalse(text.contains("<main"), "no markup survives into the answer")
        let huge = HTMLTextExtractor.cap(String(repeating: "x", count: 40_000))
        XCTAssertEqual(huge.count, HTMLTextExtractor.characterLimit, "one page, bounded")

        let binary = WebHTTPResponse(
            status: 200, data: Data([255, 254, 0, 1]), mimeType: "application/octet-stream", finalURL: nil
        )
        XCTAssertTrue(WebFetchTool.readableText(in: binary).isEmpty, "a binary body reads as nothing")
    }
}
