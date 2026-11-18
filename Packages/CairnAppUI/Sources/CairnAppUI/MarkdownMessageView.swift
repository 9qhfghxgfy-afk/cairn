import SwiftUI
import CairnChatDomain

/// An answer drawn as the Markdown it is: the same text the copy button and the export carry, so reading
/// it and taking it with you say the same thing.
///
/// While an answer is still arriving the row shows plain text instead of this, because a fence typed half
/// a sentence ago would be drawn as a code block that has not closed yet.
public struct MarkdownMessageView: View {
    let text: String

    public init(text: String) { self.text = text }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MarkdownParser.blocks(from: text).enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
            }
        }
    }
}
