import Foundation
import XCTest
import CairnChatDomain
@testable import CairnProviderRemote

/// Every way a provider can fail, each one named — and the one thing none of them may become: an empty
/// answer.
///
/// The distinction this suite exists to hold is "the provider broke" versus "it found nothing". A model
/// told the second reports to the user that nothing exists; told the first, it says its tool failed. Only a
/// test keeps a refactor from collapsing the two back into one.
///
/// No socket is opened here. `RecordingWebTransport` records the request that *would* have left, which is
/// the only place "nothing left" and "only the query left" can actually be checked.
final class WebSearchProviderFailureTests: XCTestCase {

    // MARK: the provider answered "no"

    func testARefusalIsNamedAsARefusalAndNotAsAnEmptyAnswer() async {
        let (search, transport) = searchTool(
            searchState(lanRow()), reply: .json(#"{"error":"denied"}"#, status: 403)
        )
        await expectSearchFailure(.endpointRejected) {
            try await search.execute(searchCall("rain in Paris"), context: armedContext)
        }
        XCTAssertEqual(transport.requestCount, 1, "refused once, not retried through somebody else")
    }

    func testARateLimitTellsTheModelToStopRetryingThisTurn() async {
        let (search, _) = searchTool(searchState(lanRow()), reply: .json("{}", status: 429))
        do {
            _ = try await search.execute(searchCall("rain in Paris"), context: armedContext)
            XCTFail("a 429 is a typed failure")
        } catch let thrown as ToolFailure {
            XCTAssertEqual(thrown.error, .rateLimited)
            XCTAssertTrue(
                (thrown.detail ?? "").contains("Do not retry"),
                "the model has to be told a better query will not help"
            )
        } catch {
            XCTFail("expected a typed failure, threw \(type(of: error))")
        }
    }

    func testAChallengePageIsARefusalRatherThanAMalformedAnswer() async {
        // The endpoint answers a bot challenge with an ordinary page and a 2xx status, so the only signal
        // is what the page says about itself. Read as markup-with-no-results it would become "nothing
        // exists"; read as a challenge it becomes "this client was refused", which is the truth.
        let page = "<html><body>We have detected unusual traffic from your network. "
            + "Please enter the characters in the CAPTCHA box.</body></html>"
        let (search, _) = searchTool(searchState(), reply: .html(page, status: 202))
        await expectSearchFailure(.endpointRejected) {
            try await search.execute(searchCall("rain in Paris"), context: armedContext)
        }
    }

    func testARealResultListWinsOverAChallengeWordInASnippet() async throws {
        // Someone may legitimately search the word "captcha". A page with real result anchors answered the
        // query, and reading the word alone as a block would refuse a search that worked — so the markers
        // are checked first, and only a page with no results at all is allowed to read as a challenge.
        let page = "<a class=\"result__a\" href=\"//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fcaptcha\">"
            + "What is a CAPTCHA?</a><div class=\"result__snippet\">A test of unusual traffic.</div>"
        let (search, _) = searchTool(searchState(), reply: .html(page))
        let outcome = try await search.execute(searchCall("captcha"), context: armedContext)
        XCTAssertTrue(outcome.succeeded, "a page with results answered, whatever words are in them")
        XCTAssertTrue(outcome.modelText.contains("example.com/captcha"))
    }

    // MARK: nothing answered

    func testAnUnreachableProviderIsNamedUnreachable() async {
        let (search, transport) = searchTool(
            searchState(lanRow()), throws: URLError(.cannotConnectToHost)
        )
        do {
            _ = try await search.execute(searchCall("rain in Paris"), context: armedContext)
            XCTFail("a dead address is a typed failure")
        } catch let thrown as ToolFailure {
            XCTAssertEqual(thrown.error, .endpointUnreachable)
            XCTAssertTrue((thrown.detail ?? "").contains("could not be reached"))
        } catch {
            XCTFail("expected a typed failure, threw \(type(of: error))")
        }
        XCTAssertEqual(transport.requestCount, 1, "one attempt at the row the user chose")
    }

    func testATimeoutIsATimeoutAndNotADownProvider() async {
        let (search, _) = searchTool(searchState(lanRow()), throws: URLError(.timedOut))
        await expectSearchFailure(.timedOut) {
            try await search.execute(searchCall("rain in Paris"), context: armedContext)
        }
    }

    func testACertificateFailureIsStatedAsASecurityProblem() async {
        // Distinct from "unreachable": a path exists and is not trustworthy, which is a different fix.
        let (search, _) = searchTool(searchState(lanRow()), throws: URLError(.secureConnectionFailed))
        await expectSearchFailure(.httpsRequired) {
            try await search.execute(searchCall("rain in Paris"), context: armedContext)
        }
    }

    func testCancellationIsTheTurnStoppingAndNotAProviderFailing() async {
        let (search, _) = searchTool(searchState(lanRow()), throws: URLError(.cancelled))
        await expectSearchFailure(.cancelled) {
            try await search.execute(searchCall("rain in Paris"), context: armedContext)
        }
    }

    // MARK: SearXNG's two empties, which are not the same fact

    func testAnInstanceWithNoWorkingEnginesIsNotAnEmptyAnswer() async {
        let (search, _) = searchTool(
            searchState(lanRow()),
            reply: .json(#"{"results":[],"unresponsive":[{"name":"duckduckgo"}]}"#)
        )
        do {
            _ = try await search.execute(searchCall("rain in Paris"), context: armedContext)
            XCTFail("an instance that reached nobody is not an empty web")
        } catch let thrown as ToolFailure {
            XCTAssertEqual(thrown.error, .providerUnavailable)
            XCTAssertTrue(
                (thrown.detail ?? "").contains("no working upstream engines"),
                "the model must be able to tell 'your box is down' from 'nothing exists'"
            )
        } catch {
            XCTFail("expected a typed failure, threw \(type(of: error))")
        }
    }

    func testAnEngineErrorBodyIsNotAnEmptyAnswer() async {
        let (search, _) = searchTool(
            searchState(lanRow()),
            reply: .json(#"{"error":"all engines failed to answer","results":[]}"#)
        )
        await expectSearchFailure(.providerUnavailable) {
            try await search.execute(searchCall("rain in Paris"), context: armedContext)
        }
    }

    func testAResultWithNoAddressIsDroppedRatherThanCited() async throws {
        // A result Cairn cannot name is a result a model cannot cite; numbered lines invite invention.
        let (search, _) = searchTool(
            searchState(lanRow()),
            reply: .json(#"{"results":[{"title":"Nowhere"},{"title":"Rain","url":"https://example.com/a"}]}"#)
        )
        let outcome = try await search.execute(searchCall("rain in Paris"), context: armedContext)
        XCTAssertTrue(outcome.modelText.contains("example.com/a"))
        XCTAssertFalse(outcome.modelText.contains("Nowhere"))
    }

}
