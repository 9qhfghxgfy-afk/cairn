import Foundation

/// An open or closed code fence, carrying the lines collected so far.
///
/// A fence is the only thing in Cairn's Markdown that can hold a line verbatim, and the only thing a
/// copy button hands back untouched — a code sample with its markup stripped is a broken sample. The
/// rules are CommonMark's: three or more matching markers, at most three leading spaces, and an info
/// string that names a language or names nothing.
extension MarkdownParser {
    struct Fence {
        var marker: Character
        var length: Int
        var language: String?
        var lines: [String]

        /// A line that opens a fence. A backtick fence's info string may not contain a backtick, which
        /// is what stops a run of ticks inside a block from opening a second fence inside it.
        static func openingLine(of raw: String) -> Fence? {
            guard let body = MarkdownParser.indentedBody(of: raw, allowingUpTo: 3) else { return nil }
            let chars = Array(body)
            guard let marker = chars.first, marker == "`" || marker == "~" else { return nil }
            var length = 0
            while length < chars.count, chars[length] == marker { length += 1 }
            guard length >= 3 else { return nil }
            let info = String(chars[length...]).trimmingCharacters(in: .whitespaces)
            if marker == "`", info.contains("`") { return nil }
            let language = info.isEmpty ? nil : info.lowercased()
            return Fence(marker: marker, length: length, language: language, lines: [])
        }

        /// The line that closes an open fence, carrying everything the fence held. The closing run must
        /// be at least as long as the opening one, and nothing else may sit on the line.
        static func closingLine(of raw: String, matching fence: Fence) -> [String]? {
            guard let body = MarkdownParser.indentedBody(of: raw, allowingUpTo: 3) else { return nil }
            let chars = Array(body)
            var length = 0
            while length < chars.count, chars[length] == fence.marker { length += 1 }
            guard length >= fence.length else { return nil }
            let rest = String(chars[length...]).trimmingCharacters(in: .whitespaces)
            guard rest.isEmpty else { return nil }
            return fence.lines
        }
    }
}
