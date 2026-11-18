import Foundation

/// The line shapes `MarkdownParser` recognises, each one a pure function from a line to a block.
///
/// Every recogniser allows only a shallow indent, which is CommonMark's rule: four or more leading
/// spaces is an indented block, and Cairn does not treat an indent as code. Keeping the shapes in one
/// file means the parser's loop reads as the reading order of a document rather than as string surgery.
extension MarkdownParser {

    /// `# Heading` through `###### Heading`, with the optional closing run of hashes removed.
    static func headingLine(of raw: String) -> MarkdownBlock? {
        guard let body = indentedBody(of: raw, allowingUpTo: 3) else { return nil }
        let chars = Array(body)
        var level = 0
        while level < chars.count, chars[level] == "#" { level += 1 }
        guard level >= 1, level <= 6 else { return nil }
        let after = level < chars.count ? chars[level] : " "
        guard after == " " || after == "\t" else { return nil }
        var content = String(chars[(level + 1)...]).trimmingCharacters(in: .whitespaces)
        while content.hasSuffix("#") { content = String(content.dropLast()) }
        content = content.trimmingCharacters(in: .whitespaces)
        return .heading(level: level, runs: .inline(from: content))
    }

    /// `- item`, `* item`, `+ item`, `1. item`, `4) item`. The indent becomes the nesting depth, so a
    /// nested list keeps its shape instead of flattening into the one above it.
    static func listLine(of raw: String) -> MarkdownBlock? {
        guard let body = indentedBody(of: raw, allowingUpTo: 6) else { return nil }
        let indent = raw.prefix(while: { $0 == " " || $0 == "\t" })
        let depth = indent.count >= 4 ? 2 : (indent.count >= 2 ? 1 : 0)
        let chars = Array(body)
        guard let head = chars.first else { return nil }

        if head == "-" || head == "*" || head == "+" {
            guard chars.count == 1 || chars[1] == " " || chars[1] == "\t" else { return nil }
            let content = chars.count > 1
                ? String(chars[1...]).trimmingCharacters(in: .whitespaces) : ""
            return .unorderedItem(depth: depth, runs: .inline(from: content))
        }

        var digits = 0
        while digits < chars.count, chars[digits].isNumber { digits += 1 }
        guard digits > 0, digits < chars.count, chars[digits] == "." || chars[digits] == ")" else { return nil }
        let afterDigit = chars[digits + 1]
        guard chars.count == digits + 1 || afterDigit == " " || afterDigit == "\t" else { return nil }
        let number = Int(String(chars[0..<digits])) ?? 1
        let content = chars.count > digits + 1
            ? String(chars[(digits + 1)...]).trimmingCharacters(in: .whitespaces) : ""
        return .orderedItem(number: number, depth: depth, runs: .inline(from: content))
    }

    /// `> quoted`, with the marker dropped. Consecutive quote lines join into one block.
    static func quoteLine(of raw: String) -> String? {
        guard let body = indentedBody(of: raw, allowingUpTo: 3) else { return nil }
        guard body.hasPrefix(">") else { return nil }
        return String(body.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    /// Three or more of one of `-`, `*`, `_` and nothing else on the line. Checked before the list
    /// recogniser, because `- - -` is a rule and not a bullet holding a dash.
    static func isThematicBreak(_ raw: String) -> Bool {
        let compact = raw.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3 else { return false }
        guard let only = compact.first, only == "-" || only == "*" || only == "_" else { return false }
        return compact.allSatisfy { $0 == only }
    }

    /// The line without its leading indentation, or nil when it is indented too far to be markup.
    static func indentedBody(of raw: String, allowingUpTo maximum: Int) -> String? {
        var indent = 0
        for ch in raw {
            if ch == " " { indent += 1; continue }
            if ch == "\t" { indent += 4; continue }
            break
        }
        guard indent <= maximum else { return nil }
        return String(raw.drop(while: { $0 == " " || $0 == "\t" }))
    }
}
