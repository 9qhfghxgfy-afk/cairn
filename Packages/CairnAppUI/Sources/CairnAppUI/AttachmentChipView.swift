import SwiftUI
import CairnChatDomain

/// One file a message carries, drawn as a chip: what it is, how big it is, and — for a photo whose bytes this
/// device can still read — a small picture of it.
///
/// The bytes are handed in rather than fetched here. A stored row keeps an attachment's name, size and, for a
/// document, the text Cairn read out of it, and leaves the pixels in a file beside the database; the only
/// reader of those files is `ChatSessionModel.attachmentPayload`. A view that opened one itself would be a
/// second reader with its own answer about what a conversation holds, and the two would drift apart.
///
/// A nil payload is a state, not a fault: the file was deleted in the Files app, or it arrived inside an
/// imported chat file, which carries an attachment's description and never its bytes. The chip then says so in
/// words. An empty box would read as a broken app; a sentence reads as the truth.
struct AttachmentChipView: View {
    let attachment: ChatAttachment
    /// The file's bytes when this device has them, which a staged file always does and a stored one only
    /// while its file is still there.
    let payload: Data?
    /// Present only in the composer: once a message has been sent, its files are part of the record and are
    /// not removable from the row.
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            glyph
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(isMissing ? CairnTheme.rust : CairnTheme.stoneLight)
                    .lineLimit(2)
            }
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(CairnTheme.stoneLight)
                        .padding(.leading, 2)
                }
                .accessibilityLabel("Remove \(attachment.name)")
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(CairnTheme.slate)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke((isMissing ? CairnTheme.rust : CairnTheme.stone).opacity(0.55), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    /// Size and kind, and where the file is if it is not here.
    private var detail: String {
        let basics = "\(attachment.sizeLabel) · \(attachment.kind.label)"
        return isMissing ? basics + " · not on this device" : basics
    }

    /// An image whose bytes are gone is still an image, so it keeps the photo glyph; a document whose file is
    /// gone still has the text Cairn read, which is what its row and its citations are built from.
    private var isMissing: Bool { payload?.isEmpty ?? true }

    @ViewBuilder private var glyph: some View {
        if let payload, attachment.kind.isImage, let thumbnail = ThumbnailDecoder.image(from: payload) {
            thumbnail
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: ThumbnailDecoder.maximumEdge / 3, height: ThumbnailDecoder.maximumEdge / 3)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Image(systemName: attachment.kind.isImage ? "photo" : "doc.text")
                .font(.system(size: 15))
                .foregroundStyle(isMissing ? CairnTheme.rust : CairnTheme.stoneLight)
                .frame(width: ThumbnailDecoder.maximumEdge / 3, height: ThumbnailDecoder.maximumEdge / 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(CairnTheme.stone.opacity(0.18))
                )
        }
    }
}
