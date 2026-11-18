import XCTest
@testable import CairnChatDomain

/// The calculator is the one tool whose result can be checked without a network or a model, so it
/// carries the weight of "Cairn reports only what a tool actually computed". Everything here is
/// asserted against exact text: a rounded answer and a truncated answer look the same in a test that
/// only checks "not nil".
final class CalculatorEvaluatorTests: XCTestCase {

    private func value(_ expression: String) throws -> String {
        try CalculatorEvaluator.evaluateToText(expression)
    }

    func testPrecedenceAndGrouping() throws {
        XCTAssertEqual(try value("2+3*4"), "14")
        XCTAssertEqual(try value("(2+3)*4"), "20")
        XCTAssertEqual(try value("10-2-3"), "5", "subtraction stays left-associative")
        XCTAssertEqual(try value("8/2/2"), "2")
        XCTAssertEqual(try value("2^3^2"), "512", "exponentiation is right-associative")
        XCTAssertEqual(try value("-3+5"), "2", "a leading minus is a sign, not a subtraction")
        XCTAssertEqual(try value("2 * (3 + 4) / 7"), "2")
    }

    func testFunctionsAndConstants() throws {
        XCTAssertEqual(try value("sqrt(16)"), "4")
        XCTAssertEqual(try value("max(3, 7)"), "7")
        XCTAssertEqual(try value("min(3, 7)"), "3")
        XCTAssertEqual(try value("abs(-4.5)"), "4.5")
        XCTAssertEqual(try value("round(2.467)"), "2")
        XCTAssertTrue(try value("pi").hasPrefix("3.14159"))
    }

    func testFractionsDoNotDriftIntoWholeNumbers() throws {
        XCTAssertEqual(try value("1/3"), "0.3333333333", "trailing zeros are trimmed, digits are not")
        XCTAssertEqual(try value("7/2"), "3.5")
        XCTAssertEqual(try value("0.1+0.2"), "0.3", "a sum a model would be caught out by")
    }

    func testRefusesRatherThanGuessing() {
        // Each of these has an answer a plausible parser would produce, which is the danger: a wrong
        // number returned as a fact is worse than a refusal the model can correct.
        XCTAssertThrowsError(try value("1/0")) { error in
            XCTAssertEqual(error as? CalculatorError, .divisionByZero)
        }
        XCTAssertThrowsError(try value("sqrt(-1)"))
        XCTAssertThrowsError(try value("log(0)"))
        XCTAssertThrowsError(try value("2+"))
        XCTAssertThrowsError(try value("(2+3"))
        XCTAssertThrowsError(try value("frobnicate(3)")) { error in
            XCTAssertEqual(error as? CalculatorError, .unknownFunction, "an unknown name is not a function")
        }
        XCTAssertThrowsError(try value("two + two"))
        XCTAssertThrowsError(try value("9" + String(repeating: "0", count: 600)), "an oversized literal")
    }

    func testDepthIsBoundedSoOneReplyCannotExhaustTheStack() {
        let nested = String(repeating: "(", count: 40) + "1" + String(repeating: ")", count: 40)
        XCTAssertThrowsError(try value(nested))
    }

    func testToolReportsTheAnswerAsTextTheModelCanQuote() async {
        let registry = ToolRegistry(tools: [CalculatorTool()])
        let call = ToolCall(
            id: "c1", name: "calculator",
            arguments: ["expression": .text("12 * 34")]
        )
        let outcome = await registry.execute(call, context: .forTurn(toolsEnabled: true))
        XCTAssertTrue(outcome.succeeded, outcome.detail ?? "")
        XCTAssertEqual(outcome.output, "408")
        XCTAssertTrue(outcome.modelText.contains("408"))
    }

    func testToolRefusesAMissingArgumentWithoutInventingAnAnswer() async {
        let registry = ToolRegistry(tools: [CalculatorTool()])
        let outcome = await registry.execute(
            ToolCall(id: "c1", name: "calculator", arguments: [:]),
            context: .forTurn(toolsEnabled: true)
        )
        XCTAssertEqual(outcome.error, .badArguments)
        XCTAssertTrue(outcome.modelText.contains("did not run"), "the model must be told it failed")
    }

    func testToolIsRefusedWhenTheChipIsDown() async {
        let registry = ToolRegistry(tools: [CalculatorTool()])
        let outcome = await registry.execute(
            ToolCall(id: "c1", name: "calculator", arguments: ["expression": .text("1+1")]),
            context: .forTurn(toolsEnabled: false)
        )
        XCTAssertEqual(outcome.error, .toolsOff)
    }
}
