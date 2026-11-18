import Foundation

// The text half of the extractor: entities back into characters, whitespace into lines, and a bound
// on how much of a page one tool result may carry.
extension HTMLTextExtractor {

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "mdash": "—", "ndash": "–", "hellip": "…", "rsquo": "’", "lsquo": "‘",
        "rdquo": "”", "ldquo": "“", "copy": "©", "deg": "°", "bull": "•", "trade": "™",
        "middot": "·", "times": "×", "divide": "÷", "minus": "−",
    ]

    /// Entities decoded by hand: a named one from the list a page actually uses, a numeric one by code
    /// point. An unrecognised entity is left exactly as written, because inventing a character for text
    /// the page never said is worse than leaving its markup visible.
    static func decodeEntities(_ text: String) -> String {
        var out = ""
        var remaining = Substring(text)
        while let mark = remaining.firstIndex(of: "&") {
            out += remaining[..<mark]
            let after = remaining[remaining.index(after: mark)...]
            guard let semicolon = after.firstIndex(of: ";"),
                  after.distance(from: after.startIndex, to: semicolon) <= 10 else {
                out.append("&")
                remaining = after
                continue
            }
            let body = String(after[..<semicolon])
            out.append(entity(named: body) ?? "&\(body);")
            remaining = after[after.index(after: semicolon)...]
        }
        out += remaining
        return out
    }

    private static func entity(named body: String) -> String? {
        if let named = namedEntities[body] { return named }
        guard body.hasPrefix("#") else { return nil }
        let digits = body.dropFirst()
        let isHex = digits.hasPrefix("x") || digits.hasPrefix("X")
        let scalarText = isHex ? digits.dropFirst() : digits
        guard let value = UInt32(scalarText, radix: isHex ? 16 : 10),
              let scalar = Unicode.Scalar(value) else { return nil }
        return String(Character(scalar))
    }

    /// Blank runs down to one line, and the indentation that removing markup leaves behind trimmed off.
    /// A model reads an indented wall as a signal about the page's shape that the page never gave.
    static func collapse(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    static func cap(_ text: String) -> String {
        guard text.count > characterLimit else { return text }
        return String(text.prefix(characterLimit))
    }
}
