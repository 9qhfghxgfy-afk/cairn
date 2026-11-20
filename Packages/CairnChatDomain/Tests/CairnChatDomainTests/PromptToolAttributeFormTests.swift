import Foundation
import XCTest
@testable import CairnChatDomain

/// The attribute form of the prompt protocol, read against the tools a turn actually offered.
///
/// `parse(_:)` reads two strict shapes, which is safe but narrow: a model that answers with
/// `<web_search query="Paris" />` had its markup shown to the user as answer text. A third shape is
/// only safe to read because the offered names gate it, so these cases prove both halves — what is read
/// as a call, and what still has to be treated as prose.
final class PromptToolAttributeFormTests: XCTestCase {

    private var webSearch: ToolDefinition {
        ToolDefinition(
            name: BuiltInTool.webSearch,
            blurb: "Search the web.",
            parameters: ToolParameterSchema(
                properties: [
                    "query": ToolParameter(kind: .string, description: "What to search for."),
                    "max_results": ToolParameter(kind: .integer, description: "How many results."),
                    "safe": ToolParameter(kind: .boolean, description: "Filter explicit results."),
                    "tags": ToolParameter(kind: .stringArray, description: "Restrict to tags."),
                ],
                required: ["query"]
            ),
            networkClass: .publicInternet
        )
    }

    private var location: ToolDefinition {
        ToolDefinition(
            name: BuiltInTool.getLocation, blurb: "Where is this device?",
            parameters: .none, networkClass: .onDevice
        )
    }

    /// A tool that cannot be answered by one value, so a bare body must not be guessed into it.
    private var mailer: ToolDefinition {
        ToolDefinition(
            name: BuiltInTool.composeMail, blurb: "Draft a mail.",
            parameters: ToolParameterSchema(
                properties: [
                    "to": ToolParameter(kind: .string),
                    "body": ToolParameter(kind: .string),
                ],
                required: ["to", "body"]
            )
        )
    }

    private var offered: [ToolDefinition] { [webSearch, location, mailer] }

    private func calls(_ text: String, _ offered: [ToolDefinition]? = nil) -> [ToolCallRequest] {
        PromptToolProtocol.parse(text, offered: offered ?? self.offered)
    }

    private func arguments(of call: ToolCallRequest?) -> [String: JSONValue] {
        guard let call else { return [:] }
        return JSONValue.decode(from: call.argumentsJSON)?.dictionaryValue ?? [:]
    }

    private func firstArguments(_ text: String) -> [String: JSONValue] {
        arguments(of: calls(text).first)
    }

    func testAnAttributeNameAndAQuotedValueAreRead() {
        let found = calls(#"<web_search query="Paris" />"#)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.name, BuiltInTool.webSearch)
        XCTAssertEqual(arguments(of: found.first)["query"]?.textValue, "Paris")
    }

    func testArgumentsAreTypedAgainstTheToolSchemaNotLeftAsText() {
        let arguments = firstArguments(
            #"<web_search query="Paris" max_results="5" safe="false" tags="news, tech" />"#
        )
        XCTAssertEqual(arguments["max_results"]?.intValue, 5)
        XCTAssertEqual(arguments["safe"]?.boolValue, false)
        XCTAssertEqual(arguments["tags"]?.arrayValue?.count, 2)
        XCTAssertEqual(arguments["tags"]?.arrayValue?.first?.textValue, "news")
    }

    func testAValueThatWillNotParseStaysTextForTheToolToRefuse() {
        // `max_results` is declared an integer. Reading "soon" as nil would drop the argument and leave
        // the tool answering a question the model never asked; keeping it lets the tool say what is wrong.
        XCTAssertEqual(firstArguments(#"<web_search query="Paris" max_results="soon" />"#)["max_results"]?.textValue, "soon")
    }

    func testQuotedUnquotedAndPaddedValuesAreAllRead() {
        for text in [
            #"<web_search query='Paris'/>"#,
            #"<web_search query=Paris/>"#,
            #"<web_search  query="Paris"  />"#,
        ] {
            let found = calls(text)
            XCTAssertEqual(found.count, 1, text)
            XCTAssertEqual(arguments(of: found.first)["query"]?.textValue, "Paris", text)
        }
    }

    func testABodyFillsTheOneRequiredArgument() {
        let found = calls("<web_search>Paris</web_search>")
        XCTAssertEqual(found.first?.name, BuiltInTool.webSearch)
        XCTAssertEqual(arguments(of: found.first)["query"]?.textValue, "Paris")
    }

    func testABodyIsNotGuessedIntoAToolThatNeedsTwoValues() {
        XCTAssertTrue(calls("<compose_mail>write later</compose_mail>").isEmpty)
    }

    func testATagThatTakesNothingIsACall() {
        let found = calls("<get_location />")
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.name, BuiltInTool.getLocation)
        XCTAssertTrue(arguments(of: found.first).isEmpty)
    }

    func testNamesThatWereNotOfferedStayProse() {
        let prose = #"Read the <b>bold</b> part, then follow <a href="https://example.com">this link</a>."#
        XCTAssertTrue(calls(prose).isEmpty)
        XCTAssertTrue(calls(prose, ToolRegistry(tools: [CalculatorTool()]).definitions()).isEmpty)
        XCTAssertEqual(PromptToolProtocol.strippedText(prose, offered: offered), prose)
    }

    func testMalformedMarkupIsStruckOutOfTheAnswerButNeverExecuted() {
        // `<web_search />` needs a query. Executing it would ask the tool a question the model never
        // asked; showing it would put markup in front of the user. Neither happens.
        let text = "Let me check. <web_search />"
        XCTAssertTrue(calls(text).isEmpty)
        XCTAssertEqual(PromptToolProtocol.strippedText(text, offered: offered), "Let me check.")
    }

    func testStrippedTextKeepsTheProseAroundACall() {
        let text = "Let me check.\n<web_search query=\"Paris\" />\nDone."
        XCTAssertEqual(
            PromptToolProtocol.strippedText(text, offered: offered), "Let me check.\nDone."
        )
    }

    func testATagIsNotReadUntilItsHeaderCloses() {
        XCTAssertTrue(calls(#"<web_search query="Par"#).isEmpty)
        XCTAssertTrue(calls(#"<web_search query="Paris""#).isEmpty)
        // `>` with no `/` is the same call: models leave the slash out as often as they put it in, and a
        // header that closed is a complete thought about a tool that was offered.
        XCTAssertEqual(calls(#"<web_search query="Paris">"#).count, 1)
        XCTAssertEqual(calls(#"<web_search query="Paris">Paris</web_search>"#).count, 1)
    }

    func testBothShapesInOneAnswerAreBothRead() {
        let text = "{\"name\": \"web_search\", \"arguments\": {\"query\": \"Rome\"}}\n"
            + "<web_search query=\"Paris\" />"
        let found = calls(text)
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(Set(found.map(\.name)), [BuiltInTool.webSearch])
    }

    func testTheReadIsCappedLikeEveryOtherReadHere() {
        let many = Array(repeating: #"<web_search query="Paris" />"#, count: 40)
            .joined(separator: "\n")
        XCTAssertEqual(calls(many).count, PromptToolProtocol.callLimit)
    }

    func testNoOfferedToolsMeansOnlyTheTwoStrictShapesAreRead() {
        XCTAssertTrue(PromptToolProtocol.parse(#"<web_search query="Paris" />"#, offered: []).isEmpty)
    }

    func testTheInstructionShowsTheShapeTheParserReads() {
        let block = PromptToolProtocol.instruction(for: offered)
        XCTAssertTrue(block.contains("<TOOL_NAME ARGUMENT_NAME="),
                      "the model has to be shown the form Cairn can read back")
        XCTAssertTrue(block.contains(BuiltInTool.webSearch))
    }
}
