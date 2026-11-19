import Foundation
import XCTest
@testable import CairnChatDomain

/// What a model sees on the second step of a tool loop and onward.
///
/// A native backend reads its `tools` array per request — nothing about a previous request makes a tool
/// available to the next one. The loop used to rebuild each step with the bare constructor, which dropped
/// both the definitions and the protocol: step one could be answered from the block in the system
/// message, and every step after it was a model told tools exist and shown none. On a real server that is
/// a `Tools` chip that appears to do nothing the moment a call comes back.
final class ToolLoopStepRequestTests: XCTestCase {

    private var calculator: ToolDefinition {
        ToolDefinition(
            name: BuiltInTool.calculator,
            blurb: "Evaluates one arithmetic expression.",
            parameters: ToolParameterSchema(
                properties: ["expression": ToolParameter(kind: .string, description: "Expression.")],
                required: ["expression"]
            )
        )
    }

    private func request(wireFormat: ToolCallingProtocol) -> GenerationRequest {
        GenerationRequest(
            modelID: "test-model",
            messages: [
                ChatMessagePayload(role: .system, text: "You are Cairn."),
                ChatMessagePayload(role: .user, text: "What is 12 times 34?"),
            ],
            config: .default,
            tools: [calculator],
            toolProtocol: wireFormat
        )
    }

    /// Every request the loop makes, not only the first, has to carry the tools and the dialect — or a
    /// native server answers step two with no tools in front of it.
    func testEveryStepOfTheLoopCarriesTheToolsAndTheProtocol() async throws {
        let steps = ScriptedSteps([
            [ToolTestSupport.calculatorCall()],
            [.content("It is 408.")],
        ])
        var settled: ToolLoopOutcome?
        for try await event in ToolLoop.stream(
            request: request(wireFormat: .native),
            engine: steps.engine,
            registry: ToolTestSupport.registry,
            format: .native,
            context: .forTurn(toolsEnabled: true)
        ) {
            if case .completed(let outcome) = event { settled = outcome }
        }
        let seen = steps.requests
        XCTAssertEqual(seen.count, 2, "one step to call, one to answer")
        XCTAssertEqual(settled?.run.callCount, 1)
        for (index, step) in seen.enumerated() {
            XCTAssertEqual(
                step.tools, [calculator],
                "step \(index + 1) reached the engine with no tools array"
            )
            XCTAssertEqual(
                step.toolProtocol, .native,
                "step \(index + 1) lost the wire format it was being spoken in"
            )
        }
    }

    /// The same for the fallback protocol: the block is already in the system message and survives with
    /// the history, and the protocol flag has to survive with it so a later step is still parsed as
    /// prose-wrapped calls rather than as native ones.
    func testThePromptProtocolSurvivesToTheFinalStep() async throws {
        let prose = "<function=calculator><parameter=expression>6*7</parameter></function>"
        let steps = ScriptedSteps([[.content(prose)], [.content("It is 42.")]])
        var settled: ToolLoopOutcome?
        for try await event in ToolLoop.stream(
            request: request(wireFormat: .prompt),
            engine: steps.engine,
            registry: ToolTestSupport.registry,
            format: .prompt,
            context: .forTurn(toolsEnabled: true)
        ) {
            if case .completed(let outcome) = event { settled = outcome }
        }
        let seen = steps.requests
        XCTAssertEqual(seen.count, 2)
        for step in seen {
            XCTAssertEqual(step.toolProtocol, .prompt, "every step is spoken in the prompt dialect")
            XCTAssertEqual(step.tools, [calculator])
        }
        XCTAssertEqual(settled?.run.protocolUsed, .prompt)
        XCTAssertEqual(settled?.text, "It is 42.")
    }
}
