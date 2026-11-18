import SwiftUI
import CairnChatDomain

/// What the composer says out loud about the files it is holding.
///
/// Three sentences can appear here, and each is said for a different reason:
///
/// - **A refusal** (rust): a file was not taken in. Said in rust because the user's next action is to pick a
///   different file, and nothing else on screen explains the missing chip.
/// - **The vision warning** (amber): files are staged, but no engine this turn could ask has said it can see
///   an image. Amber rather than rust because the send is not blocked in every case — a hybrid turn may reach
///   an engine that can — and because the sentence is a preview of what will happen, not a stop. It is the
///   session's own decision, so this line cannot promise something the send then refuses.
/// - **Where the files live** (stone): a temporary chat keeps nothing after the app closes, and a store that
///   could not get a directory keeps a photo only for the turn it was picked for. Both are said before the
///   user sends, because "it was there yesterday" is not a conversation anyone wants to have afterwards.
struct ComposerAttachments: View {
    let draft: ComposerDraft
    /// The session the message would go to. nil means there is no chat to send to yet, and so no engine to
    /// warn about — the composer does not invent an answer.
    let session: ChatSessionModel?
    let temporaryChat: Bool
    let storageAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !draft.isEmpty {
                PendingAttachmentChips(draft: draft)
            }
            if let refusal = draft.refusal {
                line(refusal, colour: CairnTheme.rust, symbol: "exclamationmark.arrow.triangle.2.circlepath")
            }
            if let warning = draft.visionWarning(in: session) {
                line(warning, colour: CairnTheme.amber, symbol: "eye.slash")
            }
            // Only about files that are actually here. A line about where a photograph would have been kept,
            // shown to a composer holding nothing, is noise about a decision nobody is making.
            if !draft.isEmpty,
               let notice = draft.storageNotice(temporaryChat: temporaryChat, storageAvailable: storageAvailable) {
                line(notice, colour: CairnTheme.stoneLight, symbol: "tray.and.arrow.down")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func line(_ text: String, colour: Color, symbol: String) -> some View {
        // An icon beside the words, because two of these three can be up at once and a screen full of small
        // grey text is hard to tell apart at a glance.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol).font(.caption2).foregroundStyle(colour)
            Text(text)
                .font(.caption)
                .foregroundStyle(colour)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
