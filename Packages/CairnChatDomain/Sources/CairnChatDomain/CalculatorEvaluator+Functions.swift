import Foundation

// The function table: every name the calculator accepts, with its arity, in one switch.
//
// This is the whole attack surface for a function call, and it is a closed list. A name that is not
// written here is refused with `.unknownFunction`, so nothing a model can type reaches a symbol
// lookup, a key-value path, or a format string.
extension CalculatorEvaluator {

    static func apply(_ name: String, to arguments: [Double]) throws -> Double {
        func single() throws -> Double {
            guard arguments.count == 1 else { throw CalculatorError.wrongArgumentCount }
            return arguments[0]
        }
        func pair() throws -> (Double, Double) {
            guard arguments.count == 2 else { throw CalculatorError.wrongArgumentCount }
            return (arguments[0], arguments[1])
        }
        func list() throws -> [Double] {
            guard !arguments.isEmpty else { throw CalculatorError.wrongArgumentCount }
            return arguments
        }

        switch name {
        case "sqrt":
            let value = try single()
            if value < 0 { throw CalculatorError.notFinite }
            return value.squareRoot()
        case "cbrt":
            // The standard library's cube root, not a `Double` method — and unlike `sqrt` it is
            // defined for a negative argument, so no domain guard belongs here.
            let root = Foundation.cbrt(try single())
            if !root.isFinite { throw CalculatorError.notFinite }
            return root
        case "abs": return abs(try single())
        case "negate": return -(try single())
        case "exp":
            let value = Foundation.exp(try single())
            if !value.isFinite { throw CalculatorError.notFinite }
            return value
        case "ln": return Foundation.log(try positive(try single()))
        case "log": return Foundation.log10(try positive(try single()))
        case "log2": return Foundation.log2(try positive(try single()))
        case "sin": return sin(try single())
        case "cos": return cos(try single())
        case "tan": return tan(try single())
        case "asin":
            let value = try single()
            if abs(value) > 1 { throw CalculatorError.notFinite }
            return asin(value)
        case "acos":
            let value = try single()
            if abs(value) > 1 { throw CalculatorError.notFinite }
            return acos(value)
        case "atan": return atan(try single())
        case "atan2": let (y, x) = try pair(); return atan2(y, x)
        case "round": return (try single()).rounded()
        case "floor": return floor(try single())
        case "ceil": return ceil(try single())
        case "pow": let (base, exponent) = try pair(); return try raise(base, to: exponent)
        case "min": return try list().min() ?? 0
        case "max": return try list().max() ?? 0
        case "sum": return try list().reduce(0, +)
        case "mean":
            let values = try list()
            return values.reduce(0, +) / Double(values.count)
        default:
            throw CalculatorError.unknownFunction
        }
    }

    /// Logarithms are the only place a domain matters, and a domain violation is the same class of
    /// answer as a square root of a negative: not a number, so not a result.
    private static func positive(_ value: Double) throws -> Double {
        if value <= 0 || !value.isFinite { throw CalculatorError.notFinite }
        return value
    }
}
