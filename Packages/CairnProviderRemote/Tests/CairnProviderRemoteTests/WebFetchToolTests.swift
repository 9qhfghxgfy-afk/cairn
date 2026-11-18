import Foundation
import XCTest
import CairnChatDomain
@testable import CairnProviderRemote

/// P3b fetch: the address a model typed is untrusted input, so it is refused before a byte leaves and
/// tested again after any hop.
///
/// The private targets are exactly the ones that would turn a chat window into a probe of the user's
/// own network — the router, a LAN inference box, a tunnel address — and the claim under test is that
/// Cairn sends nothing at all to them, not that it sends something and then hides the answer.
final class WebFetchToolTests: XCTestCase {

    private func call(_ url: String) -> ToolCall {
        ToolCall(id: "call-1", name: BuiltInTool.webFetch, arguments: ["url": .text(url)])
    }

    private let turn = ToolExecutionContext(toolsEnabled: true, outboundWebAllowed: true)

    /// https, a public host, and nothing that classifies as private, loopback, link-local or VPN. Each
    /// of these is a real inference or router address shape on a user's network.
    func testTheGuardRefusesEverythingButAPublicHTTPSHost() {
        XCTAssertEqual(WebFetchGuard.decision(for: URL(string: "https://example.com/page")), .allowed)
        XCTAssertEqual(WebFetchGuard.decision(for: URL(string: "http://example.com/page")), .notHTTPS)
        for blocked in [
            "https://127.0.0.1/api/tags", "https://localhost:11434/api/tags",
            "https://192.168.1.20:11434/api/tags", "https://10.8.0.1/chat",
            "https://100.64.1.2/chat", "https://172.16.0.1/chat", "https://box.local/api/tags",
        ] {
            XCTAssertEqual(
                WebFetchGuard.decision(for: URL(string: blocked)), .privateTarget,
                "\(blocked) is a private target, even over https"
            )
        }
        // The plainer reason is checked first: this address is both private and plaintext, and the
        // fetch tool's https rule is what refuses it before anything else is consulted. Cairn does
        // reach a private server over plain http — through `ServerProfile`, which is not this tool.
        XCTAssertEqual(
            WebFetchGuard.decision(for: URL(string: "http://192.168.1.20:8080/v1/models")), .notHTTPS
        )
        // Credentials in an address are refused rather than stripped: a model that typed them meant
        // them to travel, and Cairn does not carry a secret to someone else's server.
        XCTAssertEqual(
            WebFetchGuard.decision(for: URL(string: "https://user:secret@example.com")), .unusableURL
        )
        XCTAssertEqual(WebFetchGuard.decision(for: URL(string: "not-a-url-at-all")), .unusableURL)
        XCTAssertEqual(WebFetchGuard.decision(for: nil), .unusableURL)
    }

    /// Refused before the socket: a call against a private address must not open one, so the transport
    /// records nothing at all. This is the SSRF door a fetch tool exists to keep shut.
    func testAPrivateOrPlainHTTPAddressSendsNoRequestAtAll() async throws {
        for blocked in [
            "http://example.com/page", "https://127.0.0.1/api/tags", "https://localhost:11434/api",
            "https://192.168.1.20:11434/api/tags", "https://10.8.0.1/chat", "https://100.64.1.2/chat",
            "https://172.16.0.1/chat", "https://router.local/",
        ] {
            let transport = RecordingWebTransport(reply: .html("<html><body>read</body></html>"))
            do {
                _ = try await WebFetchTool(transport: transport).execute(call(blocked), context: turn)
                XCTFail("\(blocked) must never be fetched")
            } catch let failure as ToolFailure {
                XCTAssertTrue(
                    [.blockedTarget, .badArguments].contains(failure.error),
                    "\(blocked) refused with a typed reason"
                )
            }
            XCTAssertEqual(transport.requestCount, 0, "\(blocked) opened no connection")
        }
    }

    /// A hop is only allowed onward to what the same rule would have allowed in the first place, and
    /// the far side of the hop is tested again against the address the body really arrived from.
    func testARedirectOntoAPrivateAddressIsRefusedOnTheFarSideOfTheHop() async throws {
        let landing = URL(string: "http://192.168.1.20:11434/api/tags")
        let transport = RecordingWebTransport(
            reply: .html("<html><body>read</body></html>", from: landing)
        )
        do {
            _ = try await WebFetchTool(transport: transport)
                .execute(call("https://example.com/redirect"), context: turn)
            XCTFail("a body that arrived from a private address is not a page to read")
        } catch let failure as ToolFailure {
            XCTAssertEqual(failure.error, .blockedTarget)
        }
        XCTAssertEqual(transport.requestCount, 1, "the public address was fetched; the landing is refused")
    }

    /// No cookie out, none back, no credential header: a page read must not become a reader identified,
    /// and a server profile's token belongs to that profile's API and nowhere else.
    func testAFetchCarriesNoCookieAndNoCredential() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/page"))
        let request = WebFetchGuard.request(for: url, accept: "text/html")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.httpShouldHandleCookies, false, "no cookie sent, and none kept")
        XCTAssertNil(RequestReader.header(request, "Cookie"))
        XCTAssertNil(RequestReader.header(request, "Authorization"))
        XCTAssertNil(RequestReader.header(request, "Referer"))
        XCTAssertEqual(RequestReader.header(request, "Accept"), "text/html")
        XCTAssertTrue(RequestReader.header(request, "User-Agent")?.contains("Cairn") ?? false)
    }
}
