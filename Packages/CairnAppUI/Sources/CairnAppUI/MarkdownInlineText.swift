import SwiftUI
import CairnChatDomain

/// One line of an answer, with the markup the model wrote turned into attributes.
///
/// The runs come from the domain parser, so what is bold here is exactly what was bold in the text and
/// what is plain is what the model left plain. A stray delimiter never arrives as markup, which is why
/// reading an answer and copying it say the same thing.
///
/// A link is drawn as a link and opened only by the user's own tap: SwiftUI routes an
/// `AttributedString` link through the environment's `openURL`, the same single door every outbound
/// request in this app goes through. The warning that it leaves the device is the block's to show.
struct MarkdownInlineText: View {
    let runs: [MarkdownRun]
    /// The text style the line is being drawn at, so inline code inside a heading stays heading-sized.
    var base: Font.TextStyle = .body
    @Environment(\.cairnTokens) private var tokens

    var body: some View {
        Text(attributed)
            .foregroundStyle(tokens.onCanvas)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Built as one `AttributedString` rather than concatenated `Text`s, so a paragraph stays one
    /// selectable, wrapping block and a link is a real link rather than a look-alike of one.
    private var attributed: AttributedString {
        var out = AttributedString()
        for run in runs {
            var piece = AttributedString(run.text)
            switch run.style {
            case .plain:
                break
            case .strong:
                piece.font = .system(base).weight(.bold)
            case .emphasis:
                piece.font = .system(base).italic()
            case .strongEmphasis:
                piece.font = .system(base).weight(.bold).italic()
            case .code:
                piece.font = .system(base, design: .monospaced)
                piece.foregroundColor = tokens.onCanvasMuted
            case .link:
                piece.foregroundColor = tokens.accent
                piece.underline()
                if let destination = run.url, let url = URL(string: destination) {
                    piece.link = url
                }
            }
            out.append(piece)
        }
        return out
    }
}
