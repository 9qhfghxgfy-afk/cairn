import Foundation

/// One styled run of text inside a Markdown block.
///
/// The model is deliberately flat: a block is a list of runs, and a run carries its own style. That is
/// enough for what a chat answer actually contains — bold, italic, inline code, a link — and it keeps
/// the parser a single left-to-right scan with no tree to balance. A renderer walks the list and never
/// has to guess.
public struct MarkdownRun: Sendable, Equatable {
    /// How this stretch of text was marked in the source.
    public enum Style: String, Sendable, Equatable, CaseIterable {
        case plain
        case emphasis
        case strong
        case strongEmphasis
        case code
        case link
    }

    public var text: String
    public var style: Style
    /// Set only for a `.link` run. A Markdown link is the only place a Markdown block can name a
    /// destination, and it is kept as written — never resolved, never fetched.
    public var url: String?

    public init(text: String, style: Style = .plain, url: String? = nil) {
        self.text = text
        self.style = style
        self.url = url
    }

    /// A run that carries no visible style, so a parser can say "just text" in one call.
    public static func plain(_ text: String) -> MarkdownRun { MarkdownRun(text: text) }

    /// The text with its markup gone, which is what a copy button hands back and what a screen reader
    /// should speak. A link contributes its label, not its URL.
    public var spokenText: String { text }
}

public extension [MarkdownRun] {
    /// The runs joined as plain text, which is what "Copy" gives the user for a paragraph, a heading
    /// or a list item — markup is not content.
    var plainText: String { map(\.spokenText).joined() }

    /// True when nothing here is styled, which lets a renderer take the cheap path and draw one `Text`.
    var isAllPlain: Bool { allSatisfy { $0.style == .plain } }
}
