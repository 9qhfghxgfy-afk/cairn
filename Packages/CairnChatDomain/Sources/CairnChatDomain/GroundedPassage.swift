import Foundation

/// One passage taken out of a document, already numbered for the prompt and for the transcript.
///
/// A passage is a value, not a cursor into a file: it carries its own text, so a citation still reads
/// after the original file is gone, after a relaunch, and in a `.cairn` file opened on another phone.
public struct RetrievedPassage: Sendable, Equatable, Identifiable, Codable {
    public var number: Int
    public var documentID: UUID
    public var documentName: String
    public var chunkIndex: Int
    public var startCharacter: Int
    public var text: String

    public init(
        number: Int, documentID: UUID, documentName: String, chunkIndex: Int,
        startCharacter: Int, text: String
    ) {
        self.number = number
        self.documentID = documentID
        self.documentName = documentName
        self.chunkIndex = chunkIndex
        self.startCharacter = startCharacter
        self.text = text
    }

    public var id: Int { number }

    /// A short, quotable piece of the passage for a source line. Bounded characters, not a whole
    /// passage, because the row is a pointer back to the file rather than a copy of it.
    public var excerpt: String { PassageExcerpt.of(text) }
}

/// Where an answer came from, stored on the answer.
///
/// Kept apart from the passage it came from on purpose: the prompt carries the passage's text, the
/// transcript carries only enough to go and check it. That is also why a citation survives an export —
/// it names a document and a place, which is all a reader needs and none of the document itself.
public struct SourceCitation: Sendable, Equatable, Identifiable, Codable {
    public var number: Int
    public var documentName: String
    public var chunkIndex: Int
    public var startCharacter: Int
    public var excerpt: String
    public var characterCount: Int

    public init(
        number: Int, documentName: String, chunkIndex: Int, startCharacter: Int,
        excerpt: String, characterCount: Int
    ) {
        self.number = number
        self.documentName = documentName
        self.chunkIndex = chunkIndex
        self.startCharacter = startCharacter
        self.excerpt = excerpt
        self.characterCount = characterCount
    }

    public init(_ passage: RetrievedPassage) {
        self.init(
            number: passage.number,
            documentName: passage.documentName,
            chunkIndex: passage.chunkIndex,
            startCharacter: passage.startCharacter,
            excerpt: passage.excerpt,
            characterCount: passage.text.count
        )
    }

    public var id: Int { number }

    /// How the row and the transcript name a source: `[2] notes.md, from character 1_600`.
    public var label: String {
        "[\(number)] \(documentName), chunk \(chunkIndex + 1), from character \(startCharacter)"
    }
}

/// The bounded quote a source line shows.
public enum PassageExcerpt {
    public static let characterCount = 180

    public static func of(_ text: String) -> String {
        let folded = text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard folded.count > characterCount else { return folded }
        return String(folded.prefix(characterCount)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
