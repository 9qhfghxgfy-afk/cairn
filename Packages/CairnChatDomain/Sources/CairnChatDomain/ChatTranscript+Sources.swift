import Foundation

/// The lines a transcript writes about what a message carried and where its answer came from.
///
/// Both are **descriptions, never contents**. An attached photograph's bytes have no place in a Markdown file
/// a user may mail to someone or drop in a shared folder — that is a decision about where a picture goes, and
/// the user makes it per file, not as a side effect of exporting a chat. A citation's bounded quote does
/// belong here, because that quote is the thing the answer is claiming, and it is what lets a reader check
/// the claim against the file on their own phone after the file is long gone from it.
///
/// Kept apart from `ChatTranscript.swift` because these two helpers answer a question the rest of that file
/// never asks, and because the transcript's own file should stay the shape of a transcript.
extension ChatTranscript {

    /// The files a message carried: name, size and kind — plus, for a photo, the plain statement that this
    /// document does not hold its pixels. Better said here than discovered by someone whose image will not
    /// open.
    static func attachmentLines(for node: ChatNode) -> [String] {
        let attached = node.sortedAttachments
        guard !attached.isEmpty else { return [] }
        var lines: [String] = [
            "**Attached:** \(attached.map(\.summary).joined(separator: "; "))",
            "",
        ]
        for attachment in attached where attachment.kind == .image {
            lines.append("_The pixels of “\(attachment.name)” are not in this transcript — only its name and size._")
            lines.append("")
        }
        return lines
    }

    /// The sources an answer was grounded in, numbered as the prompt numbered them: the file, the place in
    /// the file, the ranking number the retrieval gave it, and a short quote to check it against.
    ///
    /// The numbering is the citation's own, not the order they arrive in: the prompt numbered the passages
    /// and the model was told to cite those numbers, so a transcript that renumbered them would break the
    /// only link between a sentence in the answer and a passage in the file.
    static func sourceLines(for node: ChatNode) -> [String] {
        guard !node.citations.isEmpty else { return [] }
        var lines: [String] = ["**Sources**", ""]
        for citation in node.citations.sorted(by: { $0.number < $1.number }) {
            let quote = citation.excerpt.isEmpty ? "" : " — “\(citation.excerpt)”"
            lines.append("- \(citation.label)\(quote)")
        }
        lines.append("")
        lines.append("_Each source names a place in a file on this device; the file itself is not here._")
        lines.append("")
        return lines
    }
}
