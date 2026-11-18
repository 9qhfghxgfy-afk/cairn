import Foundation
import CairnChatDomain

/// What the composer is holding before Send: the files the user picked, and the reason a pick was refused.
///
/// Staged here rather than in view state for three reasons. The acceptance rule (size, kind, "is this text",
/// "can this be decoded") has to be one rule a test can run without a simulator; the refusal has to survive
/// the redrawing a menu dismissal causes, so it cannot live in a `@State` that a sheet resets; and the vision
/// warning needs the whole staged set, which a per-chip view cannot see.
///
/// Nothing here writes to disk and nothing here leaves the device. Staged bytes sit in this object until the
/// session is handed them, and a file Cairn could not read is dropped with a sentence saying why — it is
/// never half-accepted, and never quietly re-typed into a different kind of thing.
@Observable @MainActor
public final class ComposerDraft {
    /// The files, in the order they arrived. Display order comes from `Attachments.sorted`, so a chip row, a
    /// transcript and a message row all agree on the order without any of them sorting twice.
    public private(set) var staged: [ChatAttachment] = []

    /// Why the last pick was refused, in the extractor's or the preparer's own words.
    ///
    /// Held on the draft rather than in the session's `lastError` because it belongs beside the paperclip the
    /// user just pressed: a refusal that appears in a banner above the transcript, or gets overwritten by an
    /// unrelated error, teaches the user nothing about the file they are holding.
    public private(set) var refusal: String?

    private let preparer: any ImagePreparing

    /// The preparer is injected because the domain cannot decode pixels. The app hands in a UIKit/ImageIO
    /// preparer that reads real dimensions and resamples to `ImagePreparationPolicy`; a host build, a
    /// preview, or a test gets `PassthroughImagePreparer`, which checks the bytes and claims nothing.
    public init(preparer: any ImagePreparing = PassthroughImagePreparer()) {
        self.preparer = preparer
    }

    public var isEmpty: Bool { staged.isEmpty }

    /// The attachments to hand to a send, in the order the app displays and exports them.
    public var attachments: [ChatAttachment] { Attachments.sorted(staged) }

    public var imageCount: Int { Attachments.images(staged).count }

    // MARK: - Taking a file

    /// Takes one picked file, deciding by the type the picker reported whether it is a picture to prepare or a
    /// document to read.
    ///
    /// The type comes from the picker rather than from the file name, because a name is what a file is called
    /// and a type is what a file is — and the difference decides whether bytes go to a model as pixels or get
    /// read here on the phone.
    public func accept(bytes: Data, name: String, isImage: Bool) {
        if isImage {
            accept(imageBytes: bytes, name: name)
        } else {
            accept(documentBytes: bytes, name: name)
        }
    }

    /// Brings a photo down to the size the policy decided, and stages what the preparer actually produced.
    public func accept(imageBytes: Data, name: String) {
        // The memory ceiling is checked before any decode is attempted: a 40 MB photo must not become a
        // decoding attempt on an 8 GB phone, and the answer to it is a sentence rather than a spinner.
        if let oversize = AttachmentCeilings.rejection(kind: .image, byteCount: imageBytes.count) {
            refusal = oversize.message
            return
        }
        switch preparer.prepare(imageBytes, name: name) {
        case .success(let prepared):
            staged.append(
                ChatAttachment.image(payload: prepared.data, name: prepared.name, declaredType: prepared.declaredType)
            )
            refusal = nil
        case .failure(let rejection):
            refusal = rejection.message
        }
    }

    /// Reads a document here on the device and stages it with the text Cairn could actually read.
    ///
    /// A PDF or a word-processing file comes back `.notPlainText` and is refused with the instruction to
    /// export it as text first. That refusal is the feature: a hand-rolled parser would return partial text
    /// with full confidence, and the user would have no way to tell the difference.
    public func accept(documentBytes: Data, name: String, declaredType: String = "public.plain-text") {
        if let oversize = AttachmentCeilings.rejection(kind: .document, byteCount: documentBytes.count) {
            refusal = oversize.message
            return
        }
        let read = DocumentTextExtractor.extract(name: name, bytes: documentBytes)
        if let rejection = read.rejected {
            refusal = rejection.message
            return
        }
        staged.append(
            ChatAttachment.document(
                payload: documentBytes, name: name, text: read.text, declaredType: declaredType
            )
        )
        refusal = nil
    }

    /// Says why a pick could not be taken in, in the caller's own words.
    ///
    /// For the failures a preparer or an extractor cannot name — a file still downloading in Files, a library
    /// item that would not transfer. The sentence belongs beside the paperclip rather than in an error banner
    /// above the transcript, because the thing it is about is the file in the user's hand.
    public func refuse(_ message: String) {
        refusal = message
    }

    // MARK: - Letting go

    public func remove(_ id: UUID) {
        staged.removeAll { $0.id == id }
    }

    /// Empties the draft after a send that really started. A refused send must not call this: the user still
    /// has the file, and the composer still says why it cannot go.
    public func clear() {
        staged.removeAll()
        refusal = nil
    }

    // MARK: - What the composer says about what it holds

    /// The standing warning while an image is staged against an engine that cannot see it. This is the
    /// session's own decision rather than a copy of it, so the line above the composer cannot promise a
    /// different outcome from the send below it.
    public func visionWarning(in session: ChatSessionModel?) -> String? {
        guard let session else { return nil }
        return session.visionWarning(for: attachments)
    }

    /// The line about where these files actually live, or nil when the app can really keep them.
    public func storageNotice(temporaryChat: Bool, storageAvailable: Bool) -> String? {
        AttachmentNotices.notice(temporaryChat: temporaryChat, storageAvailable: storageAvailable)
    }

}
