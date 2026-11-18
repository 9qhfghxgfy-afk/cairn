import Foundation

/// The three delimiter matchers behind `MarkdownRun.inline(from:)`.
///
/// Each returns the matched body plus the index just past the closing delimiter, or nil when the
/// markers do not actually close. An unmatched marker being nil — rather than an error or a greedy
/// match to end of line — is what stops a model's stray asterisk from eating the rest of its answer.
enum MarkdownInlineScanner {

    /// A backtick span. It closes on the next run of the same number of backticks and its contents are
    /// never re-parsed, which is how a literal `**` survives inside code.
    static func codeSpan(in chars: [Character], at index: Int) -> (text: String, end: Int)? {
        var fenceLength = 0
        while index + fenceLength < chars.count, chars[index + fenceLength] == "`" { fenceLength += 1 }
        var cursor = index + fenceLength
        var run = 0
        while cursor < chars.count {
            if chars[cursor] == "`" {
                run += 1
                if run == fenceLength {
                    var body = String(chars[(index + fenceLength)..<cursor])
                    // One leading and one trailing space are stripped, which is how a span can hold a
                    // literal backtick. Only strip when both are present, so content survives.
                    if body.hasPrefix(" "), body.hasSuffix(" "), body.count >= 2 {
                        body = String(body.dropFirst().dropLast())
                    }
                    return (body, cursor + run)
                }
            } else {
                run = 0
            }
            cursor += 1
        }
        return nil
    }

    /// `[label](destination)`. The label is kept as written rather than re-parsed, so a bracket inside
    /// a bracket cannot swallow a run. An unescaped space before the `)` means this was not a link.
    static func link(in chars: [Character], at index: Int) -> (label: String, url: String, end: Int)? {
        var cursor = index + 1
        var depth = 1
        var label = ""
        while cursor < chars.count {
            let ch = chars[cursor]
            if ch == "[" { depth += 1 }
            if ch == "]" { depth -= 1; cursor += 1; break }
            label.append(ch)
            cursor += 1
        }
        guard depth == 0, cursor < chars.count, chars[cursor] == "(" else { return nil }
        cursor += 1
        var url = ""
        var closed = false
        while cursor < chars.count {
            let ch = chars[cursor]
            if ch == ")" { closed = true; cursor += 1; break }
            if ch == " " || ch == "\n" { return nil }
            url.append(ch)
            cursor += 1
        }
        guard closed, !url.isEmpty else { return nil }
        return (label, url, cursor)
    }

    /// `**strong**`, `__strong__`, and the tripled forms that mean strong-plus-emphasis.
    static func strong(in chars: [Character], at index: Int) -> (text: String, triple: Bool, end: Int)? {
        let marker = chars[index]
        var length = 0
        while index + length < chars.count, chars[index + length] == marker { length += 1 }
        guard length >= 2 else { return nil }
        let triple = length >= 3
        let closeLength = triple ? 3 : 2
        let bodyStart = index + closeLength
        var cursor = bodyStart
        while cursor + closeLength - 1 < chars.count {
            if chars[cursor] == marker {
                var run = 0
                while cursor + run < chars.count, chars[cursor + run] == marker { run += 1 }
                if run >= closeLength, cursor > bodyStart {
                    return (String(chars[bodyStart..<cursor]), triple, cursor + closeLength)
                }
            }
            cursor += 1
        }
        return nil
    }

    /// `*text*` or `_text_`. A lone `_` inside a word is a snake_case letter, not emphasis, so an
    /// underscore only opens between non-word characters, and emphasis never crosses a line break.
    static func emphasis(in chars: [Character], at index: Int) -> (text: String, end: Int)? {
        let marker = chars[index]
        if marker == "_", wordCharacter(before: chars, index: index) { return nil }
        var cursor = index + 1
        var body = ""
        while cursor < chars.count {
            let ch = chars[cursor]
            if ch == "\n" { return nil }
            if ch == marker {
                if marker == "_", wordCharacter(after: chars, index: cursor) { return nil }
                if cursor > index + 1, !body.isEmpty { return (body, cursor + 1) }
            }
            body.append(ch)
            cursor += 1
        }
        return nil
    }

    private static func wordCharacter(before chars: [Character], index: Int) -> Bool {
        guard index > 0 else { return false }
        let ch = chars[index - 1]
        return ch.isLetter || ch.isNumber
    }

    private static func wordCharacter(after chars: [Character], index: Int) -> Bool {
        guard index + 1 < chars.count else { return false }
        let ch = chars[index + 1]
        return ch.isLetter || ch.isNumber
    }
}
