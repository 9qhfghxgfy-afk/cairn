import Foundation
import XCTest
@testable import CairnChatDomain

/// Hands the loop a scripted sequence of model steps.
///
/// A provider fake that answers every request the same way cannot express "calls a tool, then
/// answers", which is the whole behaviour under test — so the steps are queued, and each request
/// takes the next one.
final class ScriptedSteps: @unchecked Sendable {
    private let steps: [[StreamChunk]]
    private let lock = NSLock()
    private var index = 0

    init(_ steps: [[StreamChunk]]) {
        self.steps = steps
    }

    func next() -> [StreamChunk] {
        lock.lock()
        defer { lock.unlock() }
        defer { index += 1 }
        return index < steps.count ? steps[index] : [.content("(no more scripted steps)")]
    }

    var engine: ToolLoopEngine {
        ToolLoopEngine { _ in
            AsyncThrowingStream { continuation in
                for chunk in self.next() { continuation.yield(chunk) }
                continuation.finish()
            }
        }
    }
}

enum ToolTestSupport {
    static var registry: ToolRegistry { ToolRegistry(tools: [CalculatorTool()]) }

    static var request: GenerationRequest {
        GenerationRequest(
            modelID: "test-model",
            messages: [
                ChatMessagePayload(role: .system, text: "You are Cairn."),
                ChatMessagePayload(role: .user, text: "What is 12 times 34?"),
            ],
            config: .default
        )
    }

    static func calculatorCall(id: String = "call-1") -> StreamChunk {
        .toolCall(ToolCallRequest(
            id: id, name: "calculator", argumentsJSON: "{\"expression\":\"12*34\"}"
        ))
    }
}

/// The runtime, not the wire: every case here runs a real loop against a scripted engine and the real
/// calculator, so "the model called a tool and Cairn answered it" is proven without a server.
final class ToolLoopTests: XCTestCase {

    func testNativeCallRunsAndTheResultIsFedBackAsAToolResult() async throws {
        let steps = ScriptedSteps([
            [ToolTestSupport.calculatorCall()],
            [.content("It is 408.")],
        ])
        var outcome: ToolLoopOutcome?
        for try await event in ToolLoop.stream(
            request: ToolTestSupport.request, engine: steps.engine,
            registry: ToolTestSupport.registry, format: .native,
            context: .forTurn(toolsEnabled: true)
        ) {
            if case .completed(let settled) = event { outcome = settled }
        }
        let settled = try XCTUnwrap(outcome, "the loop must report an outcome")
        XCTAssertEqual(settled.text, "It is 408.")
        XCTAssertEqual(settled.run.callCount, 1)
        XCTAssertEqual(settled.run.invocations.first?.name, "calculator")
        XCTAssertEqual(settled.run.invocations.first?.output, "408")
        XCTAssertEqual(settled.run.protocolUsed, .native)
        XCTAssertEqual(settled.run.stepsUsed, 2, "one step to call, one to answer")
        XCTAssertFalse(settled.run.stoppedAtStepLimit)
    }

    func testASecondStepCarriesTheCallAndItsResultBackToTheModel() async throws {
        let steps = ScriptedSteps([
            [ToolTestSupport.calculatorCall()],
            [.content("done")],
        ])
        var seen: [GenerationRequest] = []
        var outcome: ToolLoopOutcome?
        let engine = ToolLoopEngine { request in
            seen.append(request)
            return AsyncThrowingStream { continuation in
                for chunk in steps.next() { continuation.yield(chunk) }
                continuation.finish()
            }
        }
        for try await event in ToolLoop.stream(
            request: ToolTestSupport.request, engine: engine,
            registry: ToolTestSupport.registry, format: .native,
            context: .forTurn(toolsEnabled: true)
        ) {
            if case .completed(let settled) = event { outcome = settled }
        }
        XCTAssertEqual(seen.count, 2)
        let second = try XCTUnwrap(seen.last)
        XCTAssertTrue(
            second.messages.contains { $0.isToolResult && $0.toolCallID == "call-1" },
            "a result must travel back against its own call id"
        )
        XCTAssertTrue(
            second.messages.contains { $0.role == .assistant && !$0.toolCalls.isEmpty },
            "the model's own call belongs in its history, not only in Cairn's record"
        )
        XCTAssertEqual(outcome?.text, "done")
    }

    func testPromptProtocolCallIsParsedOutOfProseAndNotShownToTheUser() async throws {
        let prose = "Let me work that out.\n"
            + "<function=calculator><parameter=expression>6*7</parameter></function>"
        let steps = ScriptedSteps([.content(prose), .content("It is 42.")])
        var outcome: ToolLoopOutcome?
        for try await event in ToolLoop.stream(
            request: ToolTestSupport.request, engine: steps.engine,
            registry: ToolTestSupport.registry, format: .prompt,
            context: .forTurn(toolsEnabled: true)
        ) {
            if case .completed(let settled) = event { outcome = settled }
        }
        let settled = try XCTUnwrap(outcome)
        XCTAssertEqual(settled.text, "It is 42.", "the call block is not answer text")
        XCTAssertEqual(settled.run.invocations.first?.output, "42")
        XCTAssertEqual(settled.run.protocolUsed, .prompt)
    }
}
