import Foundation

public extension [MarkdownRun] {
    /// Splits one line of Markdown into styled runs.
    ///
    /// Order of attempts at each character is code span, link, strong, emphasis, literal. That order is
    /// the whole rule set: a code span beats a delimiter inside it, a link beats a bracket, and strong
    /// beats the single marker it starts with. Anything that does not close stays literal text, so a
    /// model's stray asterisk shows up as the asterisk it wrote.
    ///
    /// It lives on the array it returns, not on `MarkdownRun`, so a caller can write `.inline(from:)`
    /// where the compiler is already expecting a list of runs.
    static func inline(from source: String) -> [MarkdownRun] {
        // `[Character](…)` and not `Array(…)`: inside an `Array` extension the bare name resolves to the
        // specialised `[MarkdownRun]`, which cannot be built from a string.
        let chars = [Character](source)
        var runs: [MarkdownRun] = []
        var literal = ""

        func flush() {
            guard !literal.isEmpty else { return }
            runs.append(.plain(literal))
            literal = ""
        }

        var index = 0
        while index < chars.count {
            let ch = chars[index]

            if ch == "`", let span = MarkdownInlineScanner.codeSpan(in: chars, at: index) {
                flush()
                runs.append(MarkdownRun(text: span.text, style: .code))
                index = span.end
                continue
            }
            if ch == "[", let found = MarkdownInlineScanner.link(in: chars, at: index) {
                flush()
                runs.append(MarkdownRun(text: found.label, style: .link, url: found.url))
                index = found.end
                continue
            }
            if (ch == "*" || ch == "_"), let found = MarkdownInlineScanner.strong(in: chars, at: index) {
                flush()
                let style: MarkdownRun.Style = found.triple ? .strongEmphasis : .strong
                runs.append(MarkdownRun(text: found.text, style: style))
                index = found.end
                continue
            }
            if (ch == "*" || ch == "_"), let found = MarkdownInlineScanner.emphasis(in: chars, at: index) {
                flush()
                runs.append(MarkdownRun(text: found.text, style: .emphasis))
                index = found.end
                continue
            }
            literal.append(ch)
            index += 1
        }
        flush()
        return runs
    }
}
