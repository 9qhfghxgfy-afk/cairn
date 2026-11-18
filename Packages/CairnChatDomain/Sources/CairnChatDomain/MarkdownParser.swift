import Foundation

/// Turns a model's answer into blocks a view can draw.
///
/// Line-based, single pass, no recursion, and bounded work: the parser never backtracks and never
/// allocates per-character state, so a long answer costs one pass over its characters. Unrecognised
/// markup is prose, never an error — a chat has to render whatever a model actually wrote.
///
/// Deliberately not handled: tables (a model's table reads as prose rather than as a mangled grid),
/// inline images (rendering one means fetching a URL, which is a network decision this module does not
/// make), and four-space indented code (guessing that an indent meant code would mis-render an indented
/// paragraph, so Cairn only treats a **fence** as code).
public enum MarkdownParser {

    public static func blocks(from source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var fence: Fence?

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(runs: .inline(from: paragraph.joined(separator: "\n"))))
            paragraph = []
        }

        func flushQuote() {
            guard !quote.isEmpty else { return }
            blocks.append(.quote(text: quote.joined(separator: "\n")))
            quote = []
        }

        for raw in lines(of: source) {
            if let open = fence {
                if let held = Fence.closingLine(of: raw, matching: open) {
                    blocks.append(.codeBlock(language: open.language, lines: held))
                    fence = nil
                } else {
                    fence?.lines.append(raw)
                }
                continue
            }

            if raw.trimmingCharacters(in: .whitespaces).isEmpty {
                flushParagraph()
                flushQuote()
                continue
            }
            if let opening = Fence.openingLine(of: raw) {
                flushParagraph()
                flushQuote()
                fence = opening
                continue
            }
            if isThematicBreak(raw) {
                flushParagraph()
                flushQuote()
                blocks.append(.thematicBreak)
                continue
            }
            if let item = listLine(of: raw) {
                flushParagraph()
                flushQuote()
                blocks.append(item)
                continue
            }
            if let heading = headingLine(of: raw) {
                flushParagraph()
                flushQuote()
                blocks.append(heading)
                continue
            }
            if let quoted = quoteLine(of: raw) {
                flushParagraph()
                quote.append(quoted)
                continue
            }
            flushQuote()
            paragraph.append(raw)
        }

        // An unterminated fence is the model running out of tokens, not a malformed answer. Everything
        // it managed to write is still shown as code, which is what the user needs to see.
        if let open = fence {
            blocks.append(.codeBlock(language: open.language, lines: open.lines))
        }
        flushParagraph()
        flushQuote()
        return blocks
    }

    /// The answer flattened to plain text, which is what the row's copy button hands back: markup is
    /// not content, so a copy of `**note**` gives `note`, and a fenced block keeps its own text whole.
    public static func plainText(from source: String) -> String {
        let blocks = blocks(from: source)
        if blocks.isEmpty { return source.trimmingCharacters(in: .whitespacesAndNewlines) }
        return blocks.plainText
    }

    /// One block per line-group with soft breaks kept, so a paragraph the model split over two lines
    /// still reads as one paragraph on screen.
    static func lines(of source: String) -> [String] {
        source.components(separatedBy: .newlines)
    }
}
