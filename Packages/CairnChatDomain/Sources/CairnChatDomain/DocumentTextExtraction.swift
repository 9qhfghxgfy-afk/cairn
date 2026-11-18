import Foundation

/// What Cairn read out of a document, and whether it had to stop reading.
public struct ExtractedDocument: Sendable, Equatable {
    public var text: String
    /// True when the text was cut at `AttachmentCeilings.extractedCharacterCount`. The stop is a fact
    /// about the read, so it is carried rather than dropped — an attachment whose tail was cut must not
    /// read as a complete document.
    public var truncated: Bool
    public var rejected: AttachmentRejection?
}

/// Reads a plain-text document on this device.
///
/// This is the whole of Cairn's document-reading story, and it is deliberately narrow. A text file is
/// decoded as UTF-8 and normalised; a binary file is refused by name with the reason, because parsing a
/// PDF or a word-processing container well enough to quote it is a project of its own, and a half-done
/// one puts invented text in front of a model. A refusal keeps the user's file intact and tells them
/// what to do instead.
///
/// Nothing here reaches a file URL, a network, or a log. Bytes in, text out, so all of it is
/// unit-testable on a host with no simulator.
public enum DocumentTextExtractor {
    /// Only the leading run is sampled for the binary test: a long text file with one stray control
    /// byte deep inside it is still text, and a PDF declares itself in its first bytes.
    static let binarySampleLength = 4096

    public static func extract(name: String, bytes: Data) -> ExtractedDocument {
        guard let oversize = AttachmentCeilings.rejection(kind: .document, byteCount: bytes.count)
        else { return decode(name: name, bytes: bytes) }
        return ExtractedDocument(text: "", truncated: false, rejected: oversize)
    }

    private static func decode(name: String, bytes: Data) -> ExtractedDocument {
        guard !looksBinary(bytes) else {
            return ExtractedDocument(text: "", truncated: false, rejected: .notPlainText)
        }
        guard let decoded = String(bytes: bytes, encoding: .utf8) else {
            return ExtractedDocument(text: "", truncated: false, rejected: .notUTF8Text)
        }
        let normalised = normalise(decoded)
        let ceiling = AttachmentCeilings.extractedCharacterCount
        let truncated = normalised.count > ceiling
        return ExtractedDocument(
            text: truncated ? String(normalised.prefix(ceiling)) : normalised,
            truncated: truncated,
            rejected: nil
        )
    }

    /// A NUL byte is the signature of a binary container; a PDF, a zip, a word-processing file and a
    /// UTF-16 file all carry one inside the first few kilobytes. Beyond that, a text file that is more
    /// than one-twentieth control characters is not prose anybody means to read.
    public static func looksBinary(_ bytes: Data) -> Bool {
        let sample = Array(bytes.prefix(binarySampleLength))
        guard !sample.isEmpty else { return false }
        var controls = 0
        for byte in sample {
            if byte == 0 { return true }
            if byte < 0x20 && byte != 0x09 && byte != 0x0A && byte != 0x0D { controls += 1 }
        }
        return controls * 20 > sample.count
    }

    /// Line endings become "\n" so chunk boundaries and character offsets mean the same thing on every
    /// file the user brings in from another system.
    public static func normalise(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// The line a transcript or a chip adds when a document's tail was cut, so a partial read is never
    /// presented as a complete one.
    public static func truncationNote(_ documentName: String) -> String {
        "Only the first \(AttachmentCeilings.extractedCharacterCount) characters of “\(documentName)” "
            + "were read on this device; the rest of the file stays unread."
    }
}
