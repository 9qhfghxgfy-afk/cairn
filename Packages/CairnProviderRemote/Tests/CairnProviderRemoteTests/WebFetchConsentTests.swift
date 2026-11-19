import Foundation
import XCTest
import CairnChatDomain
@testable import CairnProviderRemote

/// `web_fetch` shares the search tool's consent gate, and this file is why: the guard refuses a private
/// address, but a public https address is exactly the kind of thing a model can invent, and reading it is a
/// decision about the user's device rather than a decision about the model's answer.
///
/// Three conditions, the same three the search gate is tested against:
///
/// - **Nobody to ask** — a build with no sheet. Not consent: a typed refusal, and zero requests.
/// - **Asked and refused** — the same refusal, and the host is named to a person before anything is sent.
/// - **Asked and allowed** — one request, and nothing asked that the tool did not need to ask.
///
/// The claim in every case is measured on `requestCount`, because "it would not have sent it" and "it sent
/// it and then threw" look identical from the thrown error alone.
@MainActor
final class WebFetchConsentTests: XCTestCase {

    private let turn = ToolExecutionContext(toolsEnabled: true, outboundWebAllowed: true)

    private let page = "<html><body><p>Read.</p></body></html>"

    private func call(_ url: String) -> ToolCall {
        ToolCall(id: "call-1", name: BuiltInTool.webFetch, arguments: ["url": .text(url)])
    }

    /// Records the host it was shown, so the sheet's subject is asserted rather than assumed. Not
    /// main-actor-isolated as a type: the consent seam is a `@Sendable` closure, and only its `allow` method
    /// is main-actor work — the same shape `ConsentRecorder` uses in the search suite.
    private final class FetchRecorder: @unchecked Sendable {
        private var hosts: [String] = []
        private let answer: Bool
        init(answer: Bool) { self.answer = answer }

        @MainActor
        func allow(_ url: URL) -> Bool {
            hosts.append(url.host ?? "")
            return answer
        }

        var askedHosts: [String] { hosts }
    }

    /// With no seam wired, the tool has no way to have asked — so it refuses, and the refusal is the typed
    /// one a model can act on rather than a generic failure.
    func testABuildWithNobodyToAskSendsNothing() async throws {
        let transport = RecordingWebTransport(reply: .html(page))
        do {
            _ = try await WebFetchTool(transport: transport)
                .execute(call("https://example.com/page"), context: turn)
            XCTFail("nobody was asked, so nothing may be read")
        } catch let failure as ToolFailure {
            XCTAssertEqual(failure.error, .internetNotAllowed)
            XCTAssertTrue(
                (failure.detail ?? "").contains("ask"),
                "the model is told the question is still open, not that the tool is broken"
            )
        }
        XCTAssertEqual(transport.requestCount, 0, "a refusal costs no connection")
    }

    /// A person said no. The address was offered first — the host is what they read — and the tool still
    /// opens nothing.
    func testARefusalNamesTheHostAndSendsNothing() async throws {
        let recorder = FetchRecorder(answer: false)
        let transport = RecordingWebTransport(reply: .html(page))
        let tool = WebFetchTool(transport: transport, consent: { url in recorder.allow(url) })
        do {
            _ = try await tool.execute(call("https://example.com/page"), context: turn)
            XCTFail("a refused fetch must not read the page")
        } catch let failure as ToolFailure {
            XCTAssertEqual(failure.error, .internetNotAllowed)
        }
        XCTAssertEqual(recorder.askedHosts, ["example.com"], "asked about the host it was about to read")
        XCTAssertEqual(transport.requestCount, 0)
    }

    /// Allowed: one request, and the answer is the page rather than a refusal.
    func testAnAllowedFetchReadsOnce() async throws {
        let recorder = FetchRecorder(answer: true)
        let transport = RecordingWebTransport(reply: .html(page))
        let tool = WebFetchTool(transport: transport, consent: { url in recorder.allow(url) })
        let outcome = try await tool.execute(call("https://example.com/page"), context: turn)
        XCTAssertTrue(outcome.succeeded)
        XCTAssertEqual(recorder.askedHosts, ["example.com"])
        XCTAssertEqual(transport.requestCount, 1)
    }

    /// A hostile address is refused by the guard before the question is ever asked. A private target is not
    /// a thing a person is being asked to permit, and spending the prompt on it would let the tool imply
    /// that "no" was the only unsafe answer.
    func testAPrivateAddressIsRefusedBeforeTheQuestionIsAsked() async throws {
        let recorder = FetchRecorder(answer: true)
        let transport = RecordingWebTransport(reply: .html(page))
        let tool = WebFetchTool(transport: transport, consent: { url in recorder.allow(url) })
        do {
            _ = try await tool.execute(call("https://192.168.1.20:11434/api/tags"), context: turn)
            XCTFail("a private address is refused whatever the user would have answered")
        } catch let failure as ToolFailure {
            XCTAssertTrue([ToolError.blockedTarget, ToolError.badArguments].contains(failure.error))
        }
        XCTAssertEqual(recorder.askedHosts, [], "the guard answers first; the prompt is not spent")
        XCTAssertEqual(transport.requestCount, 0)
    }
}
