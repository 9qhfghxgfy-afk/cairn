import XCTest
@testable import CairnChatDomain

/// The fallback protocol, read under a bound. A model's answer is untrusted input: the parser has to
/// decline what it cannot read, stay inside its limits, and leave prose alone.
final class PromptToolProtocolTests: XCTestCase {

    func testTagFormReadsNameAndParameters() {
        let text = "<function=calculator><parameter=expression>2+2</parameter></function>"
        let calls = PromptToolProtocol.parse(text)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.name, "calculator")
        let parsed = try? JSONDecoder().decode([String: String].self, from: Data((calls.first?.argumentsJSON ?? "{}").utf8))
        XCTAssertEqual(parsed?["expression"], "2+2")
    }

    func testJSONFormIsAlsoAccepted() {
        let calls = PromptToolProtocol.parse(#"{"name": "calculator", "arguments": {"expression": "2+2"}}"#)
        XCTAssertEqual(calls.first?.name, "calculator")
        XCTAssertTrue(calls.first?.argumentsJSON.contains("expression") ?? false)
    }

    func testProseIsLeftAlone() {
        let prose = "Two plus two is four. I did not need a tool for that."
        XCTAssertTrue(PromptToolProtocol.parse(prose).isEmpty)
        XCTAssertEqual(PromptToolProtocol.strippedText(prose), prose)
    }

    func testStripRemovesTheBlockAndKeepsTheSentence() {
        let text = "Working it out now.\n<function=calculator><parameter=expression>2+2</parameter></function>"
        let kept = PromptToolProtocol.strippedText(text)
        XCTAssertEqual(kept, "Working it out now.")
    }

    func testCallsAreCappedSoOneReplyCannotSpawnAnUnboundedRun() {
        let block = "<function=calculator><parameter=expression>1+1</parameter></function>"
        let many = Array(repeating: block, count: 40).joined(separator: "\n")
        let calls = PromptToolProtocol.parse(many)
        XCTAssertEqual(calls.count, PromptToolProtocol.callLimit)
    }

    func testAnUnterminatedBlockNeverSwallowsTheWholeAnswer() {
        let text = "<function=calculator>" + String(repeating: "x", count: 9_000)
        let calls = PromptToolProtocol.parse(text)
        if let arguments = calls.first?.argumentsJSON {
            XCTAssertLessThanOrEqual(arguments.count, PromptToolProtocol.bodyCharacterLimit + 64,
                                     "an unclosed block is read to the bound, not to the end")
        }
    }

    func testInstructionNamesEveryOfferedToolAndItsArguments() {
        let block = PromptToolProtocol.instruction(
            for: ToolRegistry(tools: [CalculatorTool()]).definitions()
        )
        XCTAssertTrue(block.contains(BuiltInTool.calculator))
        XCTAssertTrue(block.contains("expression"))
        XCTAssertTrue(block.contains("<function="))
        XCTAssertTrue(PromptToolProtocol.instruction(for: []).isEmpty)
    }
}

/// A chat written before P3 has no `toolToggle` key, and must not be treated as broken: reading it
/// back keeps its persona and leaves the chip down.
final class ChatConfigDecodingTests: XCTestCase {

    func testAPreP3BlobKeepsItsPersonaAndStartsWithToolsOff() throws {
        let legacy = Data(#"{"persona":"Answer briefly."}"#.utf8)
        let config = try JSONDecoder().decode(ChatConfig.self, from: legacy)
        XCTAssertEqual(config.persona, "Answer briefly.")
        XCTAssertEqual(config.sampling, .unset)
        XCTAssertFalse(config.toolToggle.isEnabled, "a migration may not arm a chat by itself")
        XCTAssertTrue(config.toolToggle.enabledToolNames.isEmpty)
    }

    func testARoundTripKeepsTheChipAndItsSwitches() throws {
        var toggle = ToolToggleSet(isEnabled: true)
        toggle.setOn(BuiltInTool.webSearch, false)
        let config = ChatConfig(persona: "p", toolToggle: toggle)
        let decoded = try JSONDecoder().decode(
            ChatConfig.self, from: try JSONEncoder().encode(config)
        )
        XCTAssertEqual(decoded, config)
        XCTAssertTrue(decoded.toolToggle.isEnabled)
        XCTAssertFalse(decoded.toolToggle.isOn(BuiltInTool.webSearch))
        XCTAssertTrue(decoded.toolToggle.isOn(BuiltInTool.calculator))
    }
}
