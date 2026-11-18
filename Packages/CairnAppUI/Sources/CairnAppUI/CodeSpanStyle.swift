import SwiftUI
import CairnChatDomain

/// The colour a span of source gets.
///
/// Colour is the only thing this adds: a keyword is not more important than the name beside it, it is only
/// easier to find. So the whole block stays inside one family of the active theme — the accent for what a
/// language marks as structure, the plain ink for everything else — and no hue stands in for a meaning the
/// source itself does not carry.
extension CodeSpan {
    func color(in tokens: CairnThemeTokens) -> Color {
        switch kind {
        case .keyword: tokens.accent
        case .string: tokens.accent.opacity(0.75)
        case .name: tokens.onCanvas
        case .number: tokens.onCanvas.opacity(0.85)
        case .comment: tokens.onCanvasMuted
        case .plain: tokens.onCanvas
        }
    }
}

public extension [CodeSpan] {
    /// The line as SwiftUI text: monospaced throughout, coloured per span.
    func cairnHighlighted(in tokens: CairnThemeTokens) -> AttributedString {
        var out = AttributedString()
        for span in self {
            var piece = AttributedString(span.text)
            let face = Font.system(.callout, design: .monospaced)
            piece.font = span.kind == .comment ? face.italic() : face
            piece.foregroundColor = span.color(in: tokens)
            out.append(piece)
        }
        return out
    }
}
