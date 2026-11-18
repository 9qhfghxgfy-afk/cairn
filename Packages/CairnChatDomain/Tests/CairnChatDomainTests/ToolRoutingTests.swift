import XCTest
@testable import CairnChatDomain

/// Which tools a turn gets, and the guarantee underneath it: with the chip down, no tool vocabulary
/// reaches the model at all — not a filtered list, nothing.
final class ToolRoutingTests: XCTestCase {

    private let registry = ToolRegistry(tools: [CalculatorTool()])

    private func routing(on: Bool, toolCalling: Bool, only: [String]? = nil) -> ToolRouting {
        var toggle = ToolToggleSet(isEnabled: on)
        if let only {
            toggle = ToolToggleSet(isEnabled: true, webSearch: false, webFetch: false,
                                   wikiSearch: false, calculator: false, composeMail: false)
            only.forEach { toggle.setOn($0, true) }
        }
        return ToolRouting(
            toolToggle: toggle,
            capabilities: ProviderCapabilities(toolCalling: toolCalling),
            registry: registry
        )
    }

    func testChipDownOffersNothingInAnyFormat() {
        for toolCalling in [true, false] {
            let route = routing(on: false, toolCalling: toolCalling)
            XCTAssertFalse(route.offersTools)
            XCTAssertEqual(route.format, .none)
            XCTAssertTrue(route.selection(withinWordBudget: 10_000) { $0.count }.isEmpty)
            XCTAssertEqual(
                ToolSelection().instruction(format: route.format), "",
                "a tools-off turn must carry an empty tool block, not a smaller one"
            )
        }
    }

    func testFormatComesFromWhatTheBackendSaysItCanDo() {
        XCTAssertEqual(routing(on: true, toolCalling: true).format, .native)
        XCTAssertEqual(routing(on: true, toolCalling: false).format, .prompt)
    }

    func testPerToolSwitchNarrowsTheOfferedSet() {
        let route = routing(on: true, toolCalling: true, only: [BuiltInTool.calculator])
        let selection = route.selection(withinWordBudget: 10_000) { $0.count }
        XCTAssertEqual(selection.definitions.map(\.name), [BuiltInTool.calculator])
    }

    func testAnOfferThatDoesNotFitIsDroppedAndNamedRatherThanSilentlyCut() {
        let route = routing(on: true, toolCalling: false)
        let full = route.selection(withinWordBudget: 100_000) { $0.split(whereSeparator: \.isWhitespace).count }
        let tight = route.selection(withinWordBudget: 1) { $0.split(whereSeparator: \.isWhitespace).count }
        XCTAssertFalse(full.definitions.isEmpty)
        XCTAssertTrue(tight.definitions.isEmpty)
        XCTAssertEqual(Set(tight.droppedNames), Set(full.definitions.map(\.name)),
                       "what was left out is reported, so the UI can say so")
    }

    func testNativeBlockNamesTheToolsAndPromptBlockShowsTheShapes() {
        let route = routing(on: true, toolCalling: true, only: [BuiltInTool.calculator])
        let selection = route.selection(withinWordBudget: 10_000) { $0.count }
        let native = selection.instruction(format: .native)
        let prompt = selection.instruction(format: .prompt)
        XCTAssertTrue(native.contains(BuiltInTool.calculator))
        XCTAssertFalse(native.contains("<function="), "a native backend is not taught markup")
        XCTAssertTrue(prompt.contains("<function="), "a prompt-protocol model has to be shown the shape")
        XCTAssertTrue(prompt.contains(BuiltInTool.calculator))
    }
}
