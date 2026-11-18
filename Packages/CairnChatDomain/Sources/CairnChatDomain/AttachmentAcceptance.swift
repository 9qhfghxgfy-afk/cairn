import Foundation

/// Why a file could not be attached, said in the user's terms.
///
/// Every case names what the app tried to do and why it stopped, because "attach failed" is not a
/// sentence a user can act on. No case blames the file's contents — the name is echoed, never a
/// fragment of what is inside it.
public enum AttachmentRejection: String, Sendable, Equatable, LocalizedError, Codable {
    case nothingToRead
    case tooLargeToHold
    case notPlainText
    case notUTF8Text
    case unreadableImage

    public var errorDescription: String? { message }

    public var message: String {
        switch self {
        case .nothingToRead:
            return "That file has nothing in it, so there is nothing to attach."
        case .tooLargeToHold:
            return "That file is larger than this phone can safely read into memory at one go. "
                + "Share it as a smaller file, or paste the part you are asking about."
        case .notPlainText:
            return "Cairn reads plain-text documents on this device, and this file is not one. "
                + "A PDF or a word-processing file has to be exported as text first — Cairn will not "
                + "guess at what a binary format holds."
        case .notUTF8Text:
            return "That text file is not encoded as UTF-8, so Cairn cannot read it without guessing "
                + "at the characters. Re-save it as UTF-8 and attach it again."
        case .unreadableImage:
            return "That image could not be decoded on this device, so it cannot be attached."
        }
    }
}

/// Size ceilings for reading one file into memory — and nothing else.
///
/// These bound what a single read may pull into RAM on an 8 GB phone, which is a safety bound on this
/// app. They are not a count of files, not a per-conversation allowance and not a per-user allowance:
/// a conversation may carry as many attachments as the user wants, and nothing in Cairn says otherwise.
public enum AttachmentCeilings {
    /// A photo bigger than this is not decoded on a phone at one go; it says "share a smaller file".
    public static let imageByteCount = 12_000_000
    /// A text document beyond this is not read whole; retrieval would never use the tail of it anyway.
    public static let documentByteCount = 4_000_000
    /// Characters kept from one document. Past this the stored text stops, with the stop recorded.
    public static let extractedCharacterCount = 200_000

    /// nil means the file is accepted for the attempt; the extractor still gets the last word on
    /// whether the bytes are what they claim to be.
    public static func rejection(
        kind: AttachmentKind, byteCount: Int
    ) -> AttachmentRejection? {
        if byteCount <= 0 { return .nothingToRead }
        switch kind {
        case .image: return byteCount > imageByteCount ? .tooLargeToHold : nil
        case .document: return byteCount > documentByteCount ? .tooLargeToHold : nil
        }
    }
}
