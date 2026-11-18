import XCTest
@testable import CairnChatDomain

/// Colour over code, never instead of it.
///
/// The property that matters is the first one: the spans must rebuild the line exactly as written, because
/// the copy button sits beside the coloured text and a highlighter that dropped a character would hand
/// back broken code. What is coloured is the second: an unknown fence paints nothing, because colouring a
/// word by a language that does not have it tells the user something false.
final class CodeHighlighterTests: XCTestCase {

    func testSpansRebuildTheLineCharacterForCharacter() {
        let lines = [
            "let total = 42 // how many",
            "func greet(name: String) -> String { \"hi \\(name)\" }",
            "  /* block */ trailing",
            "value = 'single' + \"double\"",
            "SELECT * FROM users WHERE id = 3;",
        ]
        for language in CodeLanguage.allCases {
            var state = CodeHighlighter.ScanState()
            for line in lines {
                let spans = CodeHighlighter.spans(in: line, language: language, state: &state)
                XCTAssertEqual(spans.sourceText, line, "highlighting changed \(language.rawValue): \(line)")
            }
        }
    }

    func testKeywordsAndCommentsAreNamedAndAnOrdinaryWordIsNot() {
        var state = CodeHighlighter.ScanState()
        let spans = CodeHighlighter.spans(in: "let total = 42 // how many", language: .swift, state: &state)
        XCTAssertEqual(spans.first?.kind, .keyword)
        XCTAssertEqual(spans.first?.text, "let")
        XCTAssertEqual(spans.last?.kind, .comment)
        XCTAssertEqual(spans.last?.text, "// how many")
        // `total` is a name the model chose, not a keyword and not a type: it stays plain rather than
        // being coloured by a rule the language does not have.
        XCTAssertTrue(spans.contains { $0.kind == .number && $0.text == "42" })
        XCTAssertFalse(spans.contains { $0.kind == .name && $0.text == "total" })
    }

    func testABlockCommentOpenedOnOneLineStaysACommentToItsClose() {
        let lines = ["/* start", "still comment", "end */", "let a = 1"]
        let perLine = CodeHighlighter.spans(inBlock: lines, language: .swift)
        XCTAssertEqual(perLine[0].map(\.kind), [.comment])
        XCTAssertEqual(perLine[1].map(\.kind), [.comment])
        XCTAssertEqual(perLine[2].first?.kind, .comment)
        XCTAssertEqual(perLine[2].sourceText, lines[2])
        // The line after the close is code again, and the keyword on it is recognised again.
        XCTAssertEqual(perLine[3].first?.kind, .keyword)
        XCTAssertEqual(perLine[3].first?.text, "let")
    }

    func testAnUnknownFencePaintsNothing() {
        var state = CodeHighlighter.ScanState()
        let spans = CodeHighlighter.spans(in: "let x = 3 // note", language: .unknown, state: &state)
        XCTAssertEqual(spans.sourceText, "let x = 3 // note")
        XCTAssertFalse(spans.contains { $0.kind == .keyword })
        XCTAssertFalse(spans.contains { $0.kind == .comment })
    }

    func testJSONHasNoCommentsSoAURLIsNotOne() {
        var state = CodeHighlighter.ScanState()
        let spans = CodeHighlighter.spans(in: #"{"url": "https://example.com"}"#, language: .json, state: &state)
        XCTAssertEqual(spans.sourceText, #"{"url": "https://example.com"}"#)
        XCTAssertFalse(spans.contains { $0.kind == .comment })
    }

    func testAliasesResolveToTheSameTableAndAnAliasedNameIsNotGuessed() {
        XCTAssertEqual(CodeLanguage(infoString: "py"), .python)
        XCTAssertEqual(CodeLanguage(infoString: "ts"), .javaScript)
        XCTAssertEqual(CodeLanguage(infoString: "objective-c"), .cFamily)
        XCTAssertEqual(CodeLanguage(infoString: nil), .unknown)
        XCTAssertEqual(CodeLanguage(infoString: "brainfuck"), .unknown)
    }
}
