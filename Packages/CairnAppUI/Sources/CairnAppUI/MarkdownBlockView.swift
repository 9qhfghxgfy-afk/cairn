import SwiftUI
import CairnChatDomain

/// One block of an answer, drawn from the shape the parser found.
///
/// Each shape is drawn as the shape it is — a bullet as a bullet, a heading larger than the prose around
/// it — because flattening them loses structure the model actually wrote. Nothing is invented here: the
/// domain has no table and no image shape, so nothing here draws one, and a model's table stays the prose
/// it arrives as rather than a grid that would have to be guessed back together.
struct MarkdownBlockView: View {
    let block: MarkdownBlock
    @Environment(\.cairnTokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
            // A Markdown link is the one place an answer can name a destination, and following it leaves
            // the device. The line says so before the user taps, rather than after.
            if block.containsLink {
                Label("A link here opens outside Cairn", systemImage: "arrow.up.right.square")
                    .font(.caption2)
                    .foregroundStyle(tokens.onCanvasMuted)
            }
        }
        .padding(.leading, indentation)
    }

    @ViewBuilder private var content: some View {
        switch block {
        case .paragraph(let runs):
            MarkdownInlineText(runs: runs)

        case .heading(let level, let runs):
            MarkdownInlineText(runs: runs, base: headingStyle(level))
                .font(.system(headingStyle(level)))
                .padding(.top, level <= 2 ? 4 : 2)

        case .codeBlock(let language, let lines):
            CodeBlockView(infoString: language, lines: lines)

        case .unorderedItem(_, let runs):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\u{2022}").foregroundStyle(tokens.accent)
                MarkdownInlineText(runs: runs)
            }

        case .orderedItem(let number, _, let runs):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).")
                    .foregroundStyle(tokens.accent)
                    .monospacedDigit()
                MarkdownInlineText(runs: runs)
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(tokens.accent)
                    .frame(width: 2)
                Text(text)
                    .foregroundStyle(tokens.onCanvasMuted)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .thematicBreak:
            Divider()
        }
    }

    /// The parser counted the indent spaces, so a nested list comes out nested the way it was written.
    private var indentation: CGFloat {
        let depth: Int
        switch block {
        case .unorderedItem(let counted, _), .orderedItem(_, let counted, _): depth = counted
        default: depth = 0
        }
        return CGFloat(depth) * 14
    }

    /// A heading is bigger and firmer, not louder: the same ink as the prose around it, because size is
    /// what a heading means and a colour would be a claim about importance the text did not make. The
    /// style is handed to the inline renderer too, so inline code inside a heading stays heading-sized.
    private func headingStyle(_ level: Int) -> Font.TextStyle {
        switch level {
        case 1: .title2
        case 2: .title3
        default: .headline
        }
    }
}
