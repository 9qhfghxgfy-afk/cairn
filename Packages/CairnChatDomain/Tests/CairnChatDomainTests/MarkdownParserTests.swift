import XCTest
@testable import CairnChatDomain

/// What a model's answer becomes on the way to the screen and into the copy button.
///
/// The assertions are written against what the parser really returns, not against CommonMark as I would
/// like it to behave: unrecognised markup is prose, and a truncated answer is still shown.
final class MarkdownParserTests: XCTestCase {

    func testProseStaysProse() {
        let blocks = MarkdownParser.blocks(from: "Just a sentence.")
        XCTAssertEqual(blocks, [.paragraph(runs: [.plain("Just a sentence.")])])
    }

    func testSoftLineBreaksStayInsideOneParagraph() {
        let blocks = MarkdownParser.blocks(from: "first line\nsecond line")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks.first?.plainText, "first line\nsecond line")
    }

    func testHeadingKeepsItsLevelAndLosesItsHashes() {
        let blocks = MarkdownParser.blocks(from: "### Setup")
        XCTAssertEqual(blocks, [.heading(level: 3, runs: [.plain("Setup")])])
        // A closing run of hashes is markup the model echoed, not part of the title.
        let closed = MarkdownParser.blocks(from: "## Setup ##")
        XCTAssertEqual(closed, [.heading(level: 2, runs: [.plain("Setup")])])
    }

    func testSevenHashesIsNotAHeading() {
        let blocks = MarkdownParser.blocks(from: "####### too deep")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks.first?.plainText, "####### too deep")
    }

    func testFenceNamesItsLanguageAndKeepsEveryLineVerbatim() {
        let source = """
        ```Swift
        let x = 1
            indented as written
        ```
        """
        let blocks = MarkdownParser.blocks(from: source)
        XCTAssertEqual(blocks, [.codeBlock(language: "swift", lines: ["let x = 1", "    indented as written"])])
    }

    func testAFenceThatNeverClosesIsStillShownAsCode() {
        // This is the model running out of tokens, not a broken answer: the text that landed has to be
        // visible as code, which is the thing the user needs in front of them.
        let blocks = MarkdownParser.blocks(from: "```python\nprint(1)")
        XCTAssertEqual(blocks, [.codeBlock(language: "python", lines: ["print(1)"])])
    }

    func testTildesAndLongerFencesCloseOnlyOnTheirOwnMarker() {
        let blocks = MarkdownParser.blocks(from: "````\na ``` b\n````")
        XCTAssertEqual(blocks, [.codeBlock(language: nil, lines: ["a ``` b"])])
    }

    func testListsKeepTheirMarkerNumberAndDepth() {
        let blocks = MarkdownParser.blocks(from: "- one\n  - nested\n3) third")
        XCTAssertEqual(blocks, [
            .unorderedItem(depth: 0, runs: [.plain("one")]),
            .unorderedItem(depth: 1, runs: [.plain("nested")]),
            .orderedItem(number: 3, depth: 0, runs: [.plain("third")]),
        ])
    }

    func testQuoteLinesJoinIntoOneQuote() {
        let blocks = MarkdownParser.blocks(from: "> said one\n> said two")
        XCTAssertEqual(blocks, [.quote(text: "said one\nsaid two")])
    }

    func testThematicBreakIsCheckedBeforeTheBulletRule() {
        XCTAssertEqual(MarkdownParser.blocks(from: "- - -"), [.thematicBreak])
        XCTAssertEqual(MarkdownParser.blocks(from: "***"), [.thematicBreak])
    }

    func testFourSpaceIndentIsNotGuessedAsCode() {
        // Cairn treats only a fence as code: an indent that was meant as a paragraph keeps reading as one.
        let blocks = MarkdownParser.blocks(from: "    four spaces of prose")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertTrue(blocks[0].plainText.contains("four spaces of prose"))
    }
}
