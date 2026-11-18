import Foundation

/// Why an expression did not evaluate, as a value the model can read.
///
/// Every case is a refusal, never a crash. The calculator is the one tool whose input is entirely
/// the model's, so the parser is written by hand and bounded: no `NSExpression`, no format string
/// evaluated off an untrusted string, no symbol lookup by name. A hostile expression is ordinary
/// input here and comes back as one of these names.
public enum CalculatorError: String, Error, Sendable, Equatable, Codable, CaseIterable {
    case empty
    case tooLong
    case unknownSymbol
    case malformedNumber
    case unbalancedParentheses
    case unexpectedEnd
    case unexpectedToken
    case unknownFunction
    case wrongArgumentCount
    case unknownName
    case tooDeep
    case divisionByZero
    case notFinite

    /// Fed back to the model, because "no" with a reason stops a retry loop and a bare error does not.
    public var userText: String {
        switch self {
        case .empty: return "The expression is empty."
        case .tooLong: return "The expression is longer than the calculator accepts."
        case .unknownSymbol: return "The expression contains a symbol the calculator does not use."
        case .malformedNumber: return "The expression contains a number it cannot read."
        case .unbalancedParentheses: return "The parentheses are not balanced."
        case .unexpectedEnd: return "The expression ends too early."
        case .unexpectedToken: return "There is an unexpected token in the expression."
        case .unknownFunction: return "That function is not one the calculator provides."
        case .wrongArgumentCount: return "A function was called with the wrong number of arguments."
        case .unknownName: return "That name is not a constant the calculator provides."
        case .tooDeep: return "The expression nests too deeply."
        case .divisionByZero: return "The expression divides by zero."
        case .notFinite: return "The result is not a finite number."
        }
    }
}
