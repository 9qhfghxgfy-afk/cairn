import Foundation

/// The calculator as a tool: a thin wrapper, because the arithmetic is already pure and already
/// bounded, and a second copy of it in a networking module is a second calculator to keep in sync.
public struct CalculatorTool: ToolExecuting {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            name: BuiltInTool.calculator,
            blurb: """
                Evaluate one arithmetic expression and return its value. Supports + - * / % ^, \
                parentheses, the constants pi, tau and e, and the functions sqrt, cbrt, abs, negate, \
                exp, ln, log, log2, sin, cos, tan, asin, acos, atan, atan2, round, floor, ceil, pow, \
                min, max, sum and mean. Use it instead of doing arithmetic in your head. One \
                expression per call; if it fails, the reason is returned and you may retry once.
                """,
            parameters: ToolParameterSchema(
                properties: [
                    "expression": ToolParameter(
                        kind: .string,
                        description: "The expression, for example (2 + 3) * 4 ^ 2."
                    ),
                ],
                required: ["expression"]
            ),
            // Nothing leaves the device, so this tool is offered even with the outbound badge down.
            networkClass: .onDevice
        )
    }

    public func execute(
        _ call: ToolCall, context: ToolExecutionContext
    ) async throws -> ToolOutcome {
        guard let expression = call.arguments["expression"]?.coercedText,
              !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw ToolFailure(
                .badArguments, detail: "Give one expression in the \"expression\" argument."
            )
        }
        do {
            let answer = try CalculatorEvaluator.evaluateToText(expression)
            return .success(callID: call.id, toolName: call.name, output: answer)
        } catch let failure as CalculatorError {
            throw ToolFailure(.badArguments, detail: failure.userText)
        }
    }
}
