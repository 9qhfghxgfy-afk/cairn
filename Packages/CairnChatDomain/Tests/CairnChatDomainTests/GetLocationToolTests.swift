import Foundation
import XCTest
@testable import CairnChatDomain

/// `get_location`: the definition a model reads, and the consent order the tool runs.
///
/// Nothing here needs a device. The seam is a protocol and the consent record is an actor, so the two
/// claims that matter — a refusal performs zero work, and a refusal reaches the model as a named failure
/// rather than as an empty result — are testable on any machine with a Swift toolchain.
@MainActor
final class GetLocationToolTests: XCTestCase {

    private func registry(_ tool: any ToolExecuting) -> ToolRegistry {
        ToolRegistry(tools: [CalculatorTool(), tool])
    }

    // MARK: - What the model is told

    func testTheDefinitionIsWellFormedAndStaysOnTheDevice() {
        let definition = GetLocationTool(
            source: NoLocationSource(), consent: LocationConsentGate()
        ).definition
        XCTAssertEqual(definition.name, "get_location")
        XCTAssertTrue(definition.isWellFormed)
        XCTAssertTrue(definition.parameters.isEmpty, "the user is not an argument a model may pass")
        XCTAssertEqual(definition.networkClass, .onDevice, "no reverse geocoding, so no request")
        XCTAssertFalse(definition.requiresPublicInternet)
        XCTAssertFalse(definition.requiresNetwork)
        XCTAssertTrue(definition.blurb.contains("refused"))
        XCTAssertTrue(definition.blurb.contains("latitude"))
        XCTAssertTrue(BuiltInTool.localNames.contains(BuiltInTool.getLocation))
        XCTAssertFalse(BuiltInTool.isWebTool(BuiltInTool.getLocation))
    }

    /// The tool is offered on a chat whose outbound acknowledgement is down, because that badge is about
    /// leaving the phone, and a position read does not leave it.
    func testTheBadgeBeingDownDoesNotWithdrawTheTool() {
        let built = registry(GetLocationTool(source: RecordingLocationSource(), consent: LocationConsentGate()))
        let offered = built.availableDefinitions(
            context: ToolExecutionContext(toolsEnabled: true, outboundWebAllowed: false)
        )
        XCTAssertTrue(offered.contains { $0.name == BuiltInTool.getLocation })
    }

    func testBothPromptFormatsCarryTheRefusalRule() {
        let definition = GetLocationTool(
            source: RecordingLocationSource(), consent: LocationConsentGate()
        ).definition
        let prompt = ToolPromptBlock.render([definition], format: .prompt)
        let native = ToolPromptBlock.render([definition], format: .native)
        for block in [prompt, native] {
            XCTAssertTrue(block.contains("get_location"))
            XCTAssertTrue(block.contains("do not name a place"), block)
        }
        // An offer without the location tool gets no line about it, so nothing is added to a prompt that
        // cannot act on it.
        let calculatorOnly = ToolPromptBlock.render([CalculatorTool().definition], format: .prompt)
        XCTAssertFalse(calculatorOnly.contains("get_location"))
        XCTAssertTrue(ToolPromptBlock.guidance(for: [CalculatorTool().definition]).isEmpty)
    }
}
