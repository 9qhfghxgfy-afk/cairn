import SwiftUI
import CairnChatDomain

/// A fenced block of source: coloured, and copyable as the exact text it holds.
struct CodeBlockView: View {
    /// The fence's info string as the model wrote it. Shown as written and mapped to a highlighter
    /// language beside that, so an unknown tag is still visible to the user rather than silently dropped.
    let infoString: String?
    let lines: [String]
    @Environment(\.cairnTokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(label)
                Spacer()
                CopyButton("Copy code") { lines.joined(separator: "\n") }
                    .font(.caption2)
            }
            .font(.caption2)
            .foregroundStyle(tokens.onCanvasMuted)

            // Wrapped rather than scrolled sideways: on a phone a line that runs off the edge hides the
            // rest of itself, and a wrapped line is still the same line. The copy button is what carries
            // the source faithfully, not this rendering.
            ForEach(Array(highlighted.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tokens.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tokens.onCanvasMuted.opacity(0.25), lineWidth: 1)
        )
    }

    /// Re-derived on each pass rather than cached: a block is a dozen lines, not a transcript, and the
    /// scanner is one forward pass over them with its state carried from line to line.
    private var highlighted: [AttributedString] {
        let language = CodeLanguage(infoString: infoString)
        var state = CodeHighlighter.ScanState()
        return lines.map { line in
            CodeHighlighter.spans(in: line, language: language, state: &state).cairnHighlighted(in: tokens)
        }
    }

    private var label: String {
        let written = infoString?.trimmingCharacters(in: .whitespaces) ?? ""
        return written.isEmpty ? "code" : written
    }
}
