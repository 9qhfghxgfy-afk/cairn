import Foundation
import XCTest
@testable import CairnChatDomain

/// The loop, not only the parser: a tag has to survive the step it was written in and come back as an
/// executed call, which is the difference between a parsing test and a chat that works.
final class ToolLoopAttributeFormTests: XCTestCase {

    private var webSearch: ToolDefinition {
        ToolDefinition(
            name: BuiltInTool.webSearch, blurb: "Search the web.",
            parameters: ToolParameterSchema(
                properties: ["query": ToolParameter(kind: .string)], required: ["query"]
            ),
            networkClass: .publicInternet
        )
    }

    /// One prompt-format turn against a scripted engine, with everything the loop emitted kept.
    private func turn(
        _ steps: ScriptedSteps, tools: [ToolDefinition]
    ) async throws -> (chunks: [String], calls: [String], answer: String) {
        let request = GenerationRequest(
            modelID: "test-model",
            messages: [ChatMessagePayload(role: .user, text: "What is 12 times 34?")],
            config: .default,
            tools: tools,
            toolProtocol: .prompt
        )
        var chunks: [String] = []
        var calls: [String] = []
        var answer = ""
        for try await event in ToolLoop.stream(
            request: request, engine: steps.engine,
            registry: ToolRegistry(tools: [CalculatorTool()]), format: .prompt,
            context: ToolExecutionContext(toolsEnabled: true)
        ) {
            switch event {
            case .content(let piece): chunks.append(piece)
            case .callStarted(let invocation): calls.append(invocation.name)
            case .completed(let outcome): answer = outcome.text
            default: break
            }
        }
        return (chunks, calls, answer)
    }

    func testAnAttributeCallRunsThroughThePromptLoop() async throws {
        let steps = ScriptedSteps([
            [.content("Working. <calculator expression=\"12*34\" />")],
            [.content("It is 408.")],
        ])
        let run = try await turn(steps, tools: ToolRegistry(tools: [CalculatorTool()]).definitions())
        XCTAssertEqual(run.calls, [BuiltInTool.calculator])
        XCTAssertEqual(run.answer, "It is 408.", "the tag is not answer text")
    }

    func testMarkupTheModelCannotExecuteNeverReachesTheAnswer() async throws {
        // `<web_search />` names an offered tool but carries no query, so there is nothing to run. The
        // user still must not be shown the tag: the answer is the prose around it.
        let steps = ScriptedSteps([[.content("Sure. <web_search />")]])
        let run = try await turn(steps, tools: [webSearch])
        XCTAssertTrue(run.calls.isEmpty)
        XCTAssertEqual(run.chunks, ["Sure."])
        XCTAssertEqual(run.answer, "Sure.")
    }

    func testProseThatMentionsAToolNameIsLeftAlone() async throws {
        let steps = ScriptedSteps([[.content("I could use web_search, but I already know this one.")]])
        let run = try await turn(steps, tools: [webSearch])
        XCTAssertEqual(run.chunks, ["I could use web_search, but I already know this one."])
    }
}

