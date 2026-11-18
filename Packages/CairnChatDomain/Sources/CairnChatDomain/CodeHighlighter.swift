import Foundation

/// Colours the inside of a fenced code block.
///
/// A scanner, not a parser: it walks each line once, carries one piece of state — an open block comment —
/// across the lines of a block, and classifies a word by the language's own keyword table. It never
/// changes a character, so a block's spans rebuild exactly the text that went in, which is what makes the
/// copy button safe to place beside coloured text.
public enum CodeHighlighter {

    /// The only fact that can cross a line boundary. A block comment opened and never closed stays a
    /// comment to the end of the block rather than turning the rest of the sample plain.
    public struct ScanState: Sendable, Equatable {
        public var inBlockComment: Bool
        public init(inBlockComment: Bool = false) {
            self.inBlockComment = inBlockComment
        }
    }

    /// A whole fenced block, returning one span list per line.
    public static func spans(inBlock lines: [String], language: CodeLanguage) -> [[CodeSpan]] {
        var state = ScanState()
        return lines.map { spans(in: $0, language: language, state: &state) }
    }

    /// One line, with the scanner's state carried in and out so a multi-line comment keeps its colour.
    public static func spans(in line: String, language: CodeLanguage, state: inout ScanState) -> [CodeSpan] {
        let chars = Array(line)
        var spans: [CodeSpan] = []
        var literal = ""

        func flush() {
            guard !literal.isEmpty else { return }
            spans.append(CodeSpan(kind: .plain, text: literal))
            literal = ""
        }

        var index = 0
        if state.inBlockComment, let close = language.blockComment {
            let closeChars = Array(close.close)
            if let end = firstIndex(of: closeChars, in: chars, from: 0) {
                let stop = end + closeChars.count
                spans.append(CodeSpan(kind: .comment, text: String(chars[0..<stop])))
                state.inBlockComment = false
                index = stop
            } else {
                return [CodeSpan(kind: .comment, text: line)]
            }
        }

        while index < chars.count {
            let ch = chars[index]

            if let block = language.blockComment, has(Array(block.open), in: chars, at: index) {
                flush()
                let open = Array(block.open)
                let close = Array(block.close)
                if let end = firstIndex(of: close, in: chars, from: index + open.count) {
                    let stop = end + close.count
                    spans.append(CodeSpan(kind: .comment, text: String(chars[index..<stop])))
                    index = stop
                } else {
                    spans.append(CodeSpan(kind: .comment, text: String(chars[index...])))
                    state.inBlockComment = true
                    break
                }
                continue
            }

            if let marker = language.lineComment, has(Array(marker), in: chars, at: index) {
                flush()
                spans.append(CodeSpan(kind: .comment, text: String(chars[index...])))
                break
            }

            if language.stringDelimiters.contains(ch) {
                flush()
                let end = stringEnd(in: chars, from: index)
                spans.append(CodeSpan(kind: .string, text: String(chars[index..<end])))
                index = end
                continue
            }

            if ch.isNumber {
                flush()
                let end = numberEnd(in: chars, from: index)
                spans.append(CodeSpan(kind: .number, text: String(chars[index..<end])))
                index = end
                continue
            }

            if ch.isLetter || ch == "_" {
                let end = identifierEnd(in: chars, from: index)
                let word = String(chars[index..<end])
                flush()
                spans.append(CodeSpan(kind: kind(ofWord: word, language: language), text: word))
                index = end
                continue
            }

            literal.append(ch)
            index += 1
        }
        flush()
        return spans.coalesced
    }
}
