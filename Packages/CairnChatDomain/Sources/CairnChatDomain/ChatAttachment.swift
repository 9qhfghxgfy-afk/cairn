import Foundation

/// What kind of thing the user attached to a message, and the two kinds differ in a privacy question
/// rather than a file-type one.
///
/// An image travels to the model as pixels, and only to a model that has been observed to see them.
/// A document is read **here**, on the phone: Cairn chunks it, finds the passages that answer the
/// question, and only those passages go onward. A PDF therefore does not become "an attachment the
/// model reads" — it becomes text Cairn could read, or a refusal that says it could not.
public enum AttachmentKind: String, Sendable, Equatable, Codable, CaseIterable {
    case image
    case document

    public var isImage: Bool { self == .image }

    /// What the row says about the kind, in the row's own words rather than a file extension.
    public var label: String {
        switch self {
        case .image: return "image"
        case .document: return "document"
        }
    }
}

/// One file the user attached, carried on the message it belongs to.
///
/// It lives on the node rather than in a side table because the tree is the record: an attachment on a
/// branch has to branch, export, import and delete with that message, and a second store would give the
/// app a second and possibly different answer to "what was in this conversation".
///
/// `payload` is the user's own bytes, kept on the device. Nothing here is ever logged — the logging
/// guard exists for exactly that reason — and an attachment only leaves the device inside a request the
/// user sent, to a server the user added.
public struct ChatAttachment: Sendable, Equatable, Identifiable, Codable {
    public var id: UUID
    public var kind: AttachmentKind
    /// The user's own file name. A name, never a path: a path says where on the phone the file lives,
    /// which is a fact about the device rather than about the conversation.
    public var name: String
    /// The type the picker reported ("public.jpeg", "public.plain-text"). Descriptive only.
    public var declaredType: String
    public var byteCount: Int
    public var payload: Data
    /// Extracted text for a document, nil for an image — an image is read by a model, not by Cairn.
    public var text: String?

    public init(
        id: UUID = UUID(),
        kind: AttachmentKind,
        name: String,
        declaredType: String = "",
        byteCount: Int? = nil,
        payload: Data,
        text: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.declaredType = declaredType
        self.byteCount = byteCount ?? payload.count
        self.payload = payload
        self.text = text
    }

    /// A photo, already prepared to the size the app decided to hold.
    public static func image(
        payload: Data, name: String, declaredType: String = "public.jpeg"
    ) -> ChatAttachment {
        ChatAttachment(kind: .image, name: name, declaredType: declaredType, payload: payload)
    }

    /// A document whose text Cairn read on this device. The text travels to retrieval; the original
    /// bytes stay so the file can be exported and restored exactly as it arrived.
    public static func document(
        payload: Data, name: String, text: String, declaredType: String = "public.plain-text"
    ) -> ChatAttachment {
        ChatAttachment(
            kind: .document, name: name, declaredType: declaredType, payload: payload, text: text
        )
    }

    public var hasText: Bool { (text?.isEmpty == false) }

    /// Byte size as the user reads it, written here rather than in a view so the wording is one thing
    /// and is testable without a simulator. `ByteCountFormatter` is left alone on purpose: it changes
    /// with locale, and an attachment row should not.
    public var sizeLabel: String {
        if byteCount < 1024 { return "\(byteCount) B" }
        let kilobytes = Double(byteCount) / 1024
        if kilobytes < 1024 {
            return kilobytes >= 100
                ? String(format: "%.0f KB", kilobytes)
                : String(format: "%.1f KB", kilobytes)
        }
        return String(format: "%.1f MB", kilobytes / 1024)
    }

    /// What a chip or a transcript line says about this attachment.
    public var summary: String { "\(name) · \(sizeLabel) · \(kind.label)" }
}

/// The attachments of one turn, sorted once so a row, a transcript and an export all agree on order.
public enum Attachments {
    public static func sorted(_ attachments: [ChatAttachment]) -> [ChatAttachment] {
        attachments.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind == .image }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    public static func images(_ attachments: [ChatAttachment]) -> [ChatAttachment] {
        attachments.filter { $0.kind.isImage }
    }

    public static func documents(_ attachments: [ChatAttachment]) -> [ChatAttachment] {
        attachments.filter { $0.kind == .document }
    }
}
