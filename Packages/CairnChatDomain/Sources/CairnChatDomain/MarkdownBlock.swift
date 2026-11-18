import Foundation

/// One block of a Markdown answer.
///
/// The set is what a chat answer really contains — prose, a heading, a fenced code block, a list, a
/// quote, a rule — and nothing else. Table and image syntax are deliberately absent: a model's table
/// renders as prose rather than as a silently mangled grid, and an inline image would mean fetching a
/// remote URL, which is a network decision this module has no business making.
public enum MarkdownBlock: Sendable, Equatable {
    /// Prose. Soft line breaks inside a paragraph are kept, because a model's line break is usually a
    /// list it stopped marking or a formula it split on purpose.
    case paragraph(runs: [MarkdownRun])
    case heading(level: Int, runs: [MarkdownRun])
    /// A fenced block. `language` is the fence's info string, lowercased, or nil when the fence named
    /// none — the highlighter is honest about a language it does not know.
    case codeBlock(language: String?, lines: [String])
    case unorderedItem(depth: Int, runs: [MarkdownRun])
    case orderedItem(number: Int, depth: Int, runs: [MarkdownRun])
    /// A quote, with the `>` markers removed and its lines joined.
    case quote(text: String)
    case thematicBreak

    /// The block's text without any markup, in the order a reader would speak it. This is what a copy
    /// button hands back, and what a transcript export writes.
    public var plainText: String {
        switch self {
        case .paragraph(let runs): return runs.plainText
        case .heading(_, let runs): return runs.plainText
        case .codeBlock(_, let lines): return lines.joined(separator: "\n")
        case .unorderedItem(let depth, let runs):
            return String(repeating: "  ", count: depth) + "• " + runs.plainText
        case .orderedItem(let number, let depth, let runs):
            return String(repeating: "  ", count: depth) + "\(number). " + runs.plainText
        case .quote(let text): return text
        case .thematicBreak: return ""
        }
    }

    /// True for the one block kind that carries a destination: a paragraph or list item whose runs
    /// include a link. The UI warns on those because tapping them leaves the device.
    public var containsLink: Bool {
        switch self {
        case .paragraph(let runs), .heading(_, let runs),
             .unorderedItem(_, let runs), .orderedItem(_, _, let runs):
            return runs.contains { $0.style == .link }
        case .codeBlock, .quote, .thematicBreak:
            return false
        }
    }
}

public extension [MarkdownBlock] {
    /// Every block flattened to plain text, one block per line-group. Used by the copy button on a
    /// whole answer, so copying a formatted reply yields readable prose rather than markup.
    var plainText: String {
        compactMap { block in
            block.plainText.isEmpty ? nil : block.plainText
        }.joined(separator: "\n")
    }
}
