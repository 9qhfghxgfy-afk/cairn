import XCTest
@testable import CairnChatDomain

/// Inline markup and the plain text a copy button hands back.
///
/// The rule that matters here is that markup is not content: copying `**note**` gives `note`, and a stray
/// delimiter a model never closed stays the character it wrote rather than swallowing the rest of the
/// answer.
final class MarkdownInlineTests: XCTestCase {

    func testStrongAndEmphasisAndCodeBecomeRuns() {
        XCTAssertEqual([MarkdownRun].inline(from: "**bold**"), [MarkdownRun(text: "bold", style: .strong)])
        XCTAssertEqual([MarkdownRun].inline(from: "_slanted_"), [MarkdownRun(text: "slanted", style: .emphasis)])
        XCTAssertEqual([MarkdownRun].inline(from: "`make test`"), [MarkdownRun(text: "make test", style: .code)])
        XCTAssertEqual([MarkdownRun].inline(from: "***both***"), [MarkdownRun(text: "both", style: .strongEmphasis)])
    }

    func testPlainWordsAroundAMarkerSurvive() {
        let runs = [MarkdownRun].inline(from: "run `make test` now")
        XCTAssertEqual(runs.plainText, "run make test now")
        XCTAssertEqual(runs.map(\.style), [.plain, .code, .plain])
    }

    func testACodeSpanBeatsTheMarkupInsideIt() {
        // Backticks are a fence of their own: an asterisk in a code span is an asterisk, and colouring it
        // as emphasis would change what the command says.
        let runs = [MarkdownRun].inline(from: "`** not bold **`")
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.style, .code)
        XCTAssertEqual(runs.first?.text, "** not bold **")
    }

    func testAStrayDelimiterStaysTheCharacterTheModelWrote() {
        let runs = [MarkdownRun].inline(from: "2 * 3 * 4")
        XCTAssertEqual(runs.plainText, "2 * 3 * 4")
        XCTAssertTrue(runs.allSatisfy { $0.style == .plain })
        // The same trap with the doubled marker, and with the underscore of a filename: both are text the
        // user has to be able to copy back out unchanged.
        XCTAssertEqual(MarkdownParser.plainText(from: "2 ** 3 ** 4"), "2 ** 3 ** 4")
        XCTAssertEqual(MarkdownParser.plainText(from: "run ** a command ** now"), "run ** a command ** now")
        XCTAssertEqual(MarkdownParser.plainText(from: "some_var_name and snake_case"), "some_var_name and snake_case")
    }

    func testALinkCarriesItsDestinationAndSpeaksItsLabel() {
        let runs = [MarkdownRun].inline(from: "see [the guide](https://example.com/guide)")
        let link = runs.first { $0.style == .link }
        XCTAssertEqual(link?.text, "the guide")
        XCTAssertEqual(link?.url, "https://example.com/guide")
        // The URL is kept as written and never fetched: a Markdown block naming a destination is not the
        // app deciding to reach it.
        XCTAssertEqual(runs.plainText, "see the guide")
    }

    func testCopyHandesBackProseNotMarkup() {
        let source = """
        ## Setup

        Run `make test` **now**.

        ```sh
        make test
        ```
        """
        let copied = MarkdownParser.plainText(from: source)
        XCTAssertFalse(copied.contains("##"))
        XCTAssertFalse(copied.contains("`"))
        XCTAssertFalse(copied.contains("**"))
        XCTAssertTrue(copied.contains("Run make test now."))
        XCTAssertTrue(copied.contains("make test"))
    }

    func testOnlyABlockWithALinkSaysItCarriesOne() {
        XCTAssertTrue(MarkdownParser.blocks(from: "[label](https://example.com)").first?.containsLink == true)
        XCTAssertTrue(MarkdownParser.blocks(from: "no link here").first?.containsLink == false)
        XCTAssertTrue(MarkdownParser.blocks(from: "`[label](url)`").first?.containsLink == false)
    }
}
