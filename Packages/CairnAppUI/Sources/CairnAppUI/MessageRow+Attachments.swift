import SwiftUI
import CairnChatDomain

/// The files a message carried, and the passages an answer was built from.
///
/// Both hang off the row that owns them, for the same reason a hybrid draft card does: a source line that
/// drifts away from the sentence it belongs to stops being a citation and becomes a footnote nobody can use.
///
/// The chips read their bytes through the session (`attachmentPayload`), never off disk. A stored row carries
/// a description of a file and the text Cairn read out of it; the pixels live in a file beside the database,
/// and the session is the app's only reader of those. A document whose file has gone still shows its text and
/// still has working citations, because both were stored with the answer — which is the point of keeping a
/// citation as a place in a file rather than a pointer into one.
extension MessageRow {

    /// The files this message carried, in the order the row, the transcript and the export all use.
    @ViewBuilder var attachmentChips: some View {
        let attached = node.sortedAttachments
        if !attached.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(attached) { attachment in
                    AttachmentChipView(
                        attachment: attachment,
                        payload: session.attachmentPayload(attachment)
                    )
                }
            }
        }
    }

    /// Where a grounded answer came from, collapsed until asked for.
    ///
    /// Collapsed because a grounded answer is the thing the user came to read, and a wall of quotes in front
    /// of it buries the answer. The label still says how many sources there are, so nothing is hidden by
    /// being folded away.
    ///
    /// The numbering is the citation's own, not the order they arrive in: the prompt numbered the passages and
    /// the model was told to cite those numbers, so renumbering here would break the only link between a
    /// sentence in the answer and a passage in the file.
    @ViewBuilder var sourceList: some View {
        if !node.citations.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(node.citations.sorted { $0.number < $1.number }) { citation in
                        citationRow(citation)
                    }
                    Text("Each source names a place in a file on this device.")
                        .font(.caption2)
                        .foregroundStyle(CairnTheme.stoneLight)
                        .padding(.top, 2)
                }
                .padding(.top, 6)
            } label: {
                Label("Sources (\(node.citations.count))", systemImage: "text.book.closed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CairnTheme.moss)
            }
            .tint(CairnTheme.moss)
        }
    }

    private func citationRow(_ citation: SourceCitation) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(citation.label)
                .font(.caption2.monospaced())
                .foregroundStyle(CairnTheme.stoneLight)
                .textSelection(.enabled)
            if !citation.excerpt.isEmpty {
                Text("“\(citation.excerpt)”")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(CairnTheme.stone)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Source \(citation.label). Quoted: \(citation.excerpt)")
    }
}
