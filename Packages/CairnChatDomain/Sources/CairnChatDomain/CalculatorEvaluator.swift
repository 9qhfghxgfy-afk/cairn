import Foundation

/// A hand-written recursive-descent calculator: `+ - * / % ^`, parentheses, constants, and a fixed
/// function table.
///
/// Nothing here evaluates a string. There is no `NSExpression`, no `value(forKey:)`, no selector
/// built from a name — the expression is tokenised, then parsed by grammar, and both passes are
/// bounded (length, token count, nesting depth). That matters because the input is whatever a model
/// emitted, and a model will eventually emit something hostile by accident. The answer to that is a
/// typed `CalculatorError`, never a crash and never code execution.
///
/// Precedence, tightest first: parentheses/function → unary `-`/`+` → `^` (right-associative) →
/// `*  /  %` → `+  -`. `-2^2` is `-4`, which is what a mathematician means by it.
public enum CalculatorEvaluator {
    public static let characterLimit = 512
    public static let tokenLimit = 200
    public static let depthLimit = 16

    public static func evaluate(_ raw: String) throws -> Double {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { throw CalculatorError.empty }
        if text.count > characterLimit { throw CalculatorError.tooLong }

        var tokenizer = Tokenizer(text)
        let tokens = try tokenizer.tokenize()
        if tokens.isEmpty { throw CalculatorError.empty }
        if tokens.count > tokenLimit { throw CalculatorError.tooLong }

        var parser = Parser(tokens: tokens)
        let value = try parser.parseExpression()
        if !parser.atEnd { throw CalculatorError.unexpectedToken }
        if !value.isFinite { throw CalculatorError.notFinite }
        return value
    }

    /// Evaluates and renders in one step, which is what the tool returns.
    public static func evaluateToText(_ raw: String) throws -> String {
        format(try evaluate(raw))
    }

    /// Integers print without a decimal point, so `2 + 2` reads as `4` and not `4.0`.
    public static func format(_ value: Double) -> String {
        guard value.isFinite else { return "undefined" }
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        return String(format: "%.10g", value)
    }
}

extension CalculatorEvaluator {

    enum Token: Equatable {
        case number(Double)
        case symbol(String)
        case name(String)
    }

    struct Tokenizer {
        let characters: [Character]
        var index = 0

        init(_ text: String) { characters = Array(text) }

        mutating func tokenize() throws -> [Token] {
            var tokens: [Token] = []
            while index < characters.count {
                let character = characters[index]
                if character.isWhitespace { index += 1; continue }
                if character.isNumber || character == "." {
                    tokens.append(try readNumber()); continue
                }
                if character.isLetter || character == "_" {
                    tokens.append(.name(readName())); continue
                }
                if "+-*/%^(),".contains(character) {
                    tokens.append(.symbol(String(character))); index += 1; continue
                }
                // The characters a model reaches for instead of ASCII, all three of which arrive
                // from copy-paste often enough to be worth reading rather than rejecting.
                if character == "−" || character == "–" {
                    tokens.append(.symbol("-")); index += 1; continue
                }
                if character == "×" { tokens.append(.symbol("*")); index += 1; continue }
                if character == "÷" { tokens.append(.symbol("/")); index += 1; continue }
                throw CalculatorError.unknownSymbol
            }
            return tokens
        }

        private mutating func readNumber() throws -> Token {
            var text = ""
            var sawDot = false
            while index < characters.count {
                let character = characters[index]
                if character.isNumber { text.append(character); index += 1; continue }
                if character == "." && !sawDot { sawDot = true; text.append(character); index += 1; continue }
                break
            }
            // An exponent is only an exponent when a digit or sign follows the `e`; otherwise `e`
            // belongs to whatever comes next and reading it here would eat a name.
            if index < characters.count, characters[index] == "e" || characters[index] == "E" {
                let lookahead = index + 1 < characters.count ? characters[index + 1] : " "
                if lookahead.isNumber || lookahead == "-" || lookahead == "+" {
                    text.append("e"); index += 1
                    if characters[index] == "-" || characters[index] == "+" {
                        text.append(characters[index]); index += 1
                    }
                    while index < characters.count, characters[index].isNumber {
                        text.append(characters[index]); index += 1
                    }
                }
            }
            guard !text.isEmpty, text != ".", let value = Double(text), value.isFinite else {
                throw CalculatorError.malformedNumber
            }
            return .number(value)
        }

        private mutating func readName() -> String {
            var text = ""
            while index < characters.count {
                let character = characters[index]
                if character.isLetter || character.isNumber || character == "_" {
                    text.append(character); index += 1
                } else { break }
            }
            return text.lowercased()
        }
    }
}
