import SwiftUI
import CairnChatDomain

/// The files sitting in the composer, waiting for Send, each with the way to take it back out.
///
/// Staged chips show the bytes that are in memory, because the user picked them seconds ago and nothing has
/// written them anywhere yet — there is no file to read back, and pretending otherwise would make the chip a
/// claim about disk state it has no business making.
///
/// The order is the order a row, a transcript and an export all use, so a photo the user picked first is the
/// first photo in the message everywhere it is written down.
struct PendingAttachmentChips: View {
    let draft: ComposerDraft

    var body: some View {
        // Horizontal, because a phone composer has no vertical room and a second photo is not worth pushing
        // the text field off screen. The count in the accessibility label is what tells a screen reader how
        // many more there are off the edge.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(draft.staged) { attachment in
                    AttachmentChipView(attachment: attachment, payload: attachment.payload) {
                        draft.remove(attachment.id)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Attached to this message: " + draft.staged.map { $0.name }.joined(separator: ", "))
    }
}
