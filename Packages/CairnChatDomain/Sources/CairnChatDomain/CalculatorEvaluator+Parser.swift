import Foundation

// The grammar half of the calculator, kept apart from the tokenizer so each file reads as one
// thing: this file is precedence, the other file is characters.
extension CalculatorEvaluator {

    struct Parser {
        let tokens: [Token]
        var position = 0
        var depth = 0

        init(tokens: [Token]) { self.tokens = tokens }

        var atEnd: Bool { position >= tokens.count }
        private var current: Token? { position < tokens.count ? tokens[position] : nil }

        private mutating func advance() { position += 1 }

        private mutating func match(_ symbol: String) -> Bool {
            guard case .symbol(symbol)? = current else { return false }
            advance()
            return true
        }

        private mutating func expect(_ symbol: String) throws {
            if !match(symbol) { throw CalculatorError.unbalancedParentheses }
        }

        private mutating func enter() throws {
            depth += 1
            if depth > CalculatorEvaluator.depthLimit { throw CalculatorError.tooDeep }
        }

        private mutating func leave() { depth -= 1 }

        mutating func parseExpression() throws -> Double {
            try enter()
            defer { leave() }
            var value = try parseTerm()
            while true {
                if match("+") { value += try parseTerm(); continue }
                if match("-") { value -= try parseTerm(); continue }
                return value
            }
        }

        private mutating func parseTerm() throws -> Double {
            var value = try parseUnary()
            while true {
                if match("*") { value *= try parseUnary(); continue }
                if match("/") {
                    let divisor = try parseUnary()
                    if divisor == 0 { throw CalculatorError.divisionByZero }
                    value /= divisor
                    continue
                }
                if match("%") {
                    let divisor = try parseUnary()
                    if divisor == 0 { throw CalculatorError.divisionByZero }
                    value = value.truncatingRemainder(dividingBy: divisor)
                    continue
                }
                return value
            }
        }

        private mutating func parseUnary() throws -> Double {
            if match("-") { return -(try parseUnary()) }
            if match("+") { return try parseUnary() }
            return try parsePower()
        }

        /// Right-associative, so `2^3^2` is `2^(3^2)` = 512 rather than 64.
        private mutating func parsePower() throws -> Double {
            let base = try parsePrimary()
            guard match("^") else { return base }
            let exponent = try parseUnary()
            return try Self.raise(base, to: exponent)
        }

        private mutating func parsePrimary() throws -> Double {
            guard let token = current else { throw CalculatorError.unexpectedEnd }
            switch token {
            case .number(let value):
                advance()
                return value
            case .symbol("("):
                advance()
                try enter()
                let value = try parseExpression()
                leave()
                try expect(")")
                return value
            case .name(let identifier):
                advance()
                return try parseCallOrConstant(identifier)
            case .symbol:
                throw CalculatorError.unexpectedToken
            }
        }

        private mutating func parseCallOrConstant(_ identifier: String) throws -> Double {
            guard match("(") else { return try Self.constant(identifier) }
            try enter()
            var arguments: [Double] = []
            if !match(")") {
                while true {
                    arguments.append(try parseExpression())
                    if match(",") { continue }
                    if match(")") { break }
                    throw CalculatorError.unexpectedToken
                }
            }
            leave()
            return try Self.apply(identifier, to: arguments)
        }
    }

    static func constant(_ identifier: String) throws -> Double {
        switch identifier {
        case "pi": return Double.pi
        case "tau": return Double.pi * 2
        case "e": return M_E
        default: throw CalculatorError.unknownName
        }
    }

    /// `pow` is guarded rather than called directly: `0 ^ -1` is infinity, and infinity reported as
    /// an answer is a wrong answer, not a result.
    static func raise(_ base: Double, to exponent: Double) throws -> Double {
        let value = Foundation.pow(base, exponent)
        if !value.isFinite { throw CalculatorError.notFinite }
        return value
    }
}
