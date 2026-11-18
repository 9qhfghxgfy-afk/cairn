import Foundation

/// The character classes behind `CodeHighlighter`.
///
/// Each helper returns an index just past the run it consumed, so the scanner never re-reads a character
/// and a pathological line costs one pass. Keeping the classes here rather than inline keeps the scan loop
/// readable as the order things are recognised in — comment, string, number, word, everything else.
extension CodeHighlighter {

    /// Whether `needle` sits at `index`. Used for two-character markers (`//`, `--`, `/*`) that a
    /// character test cannot express.
    static func has(_ needle: [Character], in chars: [Character], at index: Int) -> Bool {
        guard index + needle.count <= chars.count else { return false }
        for offset in 0..<needle.count where chars[index + offset] != needle[offset] { return false }
        return true
    }

    static func firstIndex(of needle: [Character], in chars: [Character], from index: Int) -> Int? {
        var cursor = max(index, 0)
        while cursor + needle.count <= chars.count {
            if has(needle, in: chars, at: cursor) { return cursor }
            cursor += 1
        }
        return nil
    }

    /// The index just past a string literal. A backslash escapes the next character, and a literal the
    /// model never closed runs to the end of the line rather than swallowing the rest of the block — an
    /// unterminated quote is a truncated answer, and the rest of the sample is still code.
    static func stringEnd(in chars: [Character], from index: Int) -> Int {
        let quote = chars[index]
        var cursor = index + 1
        while cursor < chars.count {
            let ch = chars[cursor]
            if ch == "\\", cursor + 1 < chars.count { cursor += 2; continue }
            cursor += 1
            if ch == quote { return cursor }
        }
        return chars.count
    }

    /// A number: digits, a radix prefix, a decimal point, and digit separators. Stops at an operator or
    /// a name, so `1and2` is not read as one literal.
    static func numberEnd(in chars: [Character], from index: Int) -> Int {
        var cursor = index
        while cursor < chars.count {
            let ch = chars[cursor]
            if ch.isNumber || ch == "_" { cursor += 1; continue }
            if ch.isLetter || ch == "." {
                // A dot only belongs to the number while digits follow it, so a trailing period that
                // ends a sentence in prose-in-code does not join two runs.
                if ch == ".", cursor + 1 < chars.count, chars[cursor + 1].isNumber { cursor += 1; continue }
                if ch.isLetter { cursor += 1; continue }
                break
            }
            break
        }
        return cursor
    }

    /// An identifier, including Swift's and Ruby's trailing `?` and `!`. A dot is **not** part of it:
    /// `Foo.bar` is two words, and reading it as one would colour a member access by the type's rule.
    static func identifierEnd(in chars: [Character], from index: Int) -> Int {
        var cursor = index
        while cursor < chars.count {
            let ch = chars[cursor]
            if ch.isLetter || ch.isNumber || ch == "_" || ch == "?" || ch == "!" || ch == "$" {
                cursor += 1
                continue
            }
            break
        }
        return cursor
    }

    /// A keyword this language has, a name worth naming, or plain text. SQL is case-insensitive, so its
    /// words are looked up in lowercase; every other language is matched as written.
    static func kind(ofWord word: String, language: CodeLanguage) -> CodeSpan.Kind {
        let probe = language == .sql ? word.lowercased() : word
        if language.keywords.contains(probe) { return .keyword }
        if language.namesTypesByCapital, let first = word.first, first.isUppercase { return .name }
        return .plain
    }
}
