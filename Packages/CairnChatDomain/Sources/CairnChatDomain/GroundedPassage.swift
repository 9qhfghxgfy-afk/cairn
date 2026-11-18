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
    /// The ranking number that put this passage where it is. Optional because a passage written before M6
    /// carried none, and because a caller may build one by hand — the absence is recorded rather than filled
    /// in with a plausible zero.
    public var score: Double?

    public init(
        number: Int, documentID: UUID, documentName: String, chunkIndex: Int,
        startCharacter: Int, text: String, score: Double? = nil
    ) {
        self.number = number
        self.documentID = documentID
        self.documentName = documentName
        self.chunkIndex = chunkIndex
        self.startCharacter = startCharacter
        self.text = text
        self.score = score
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
    /// The retrieval score that ranked this passage, when the turn that produced it had one. Kept because a
    /// source line is worth more with "this was the strongest match" than without it, and optional because
    /// a citation written before M6 carried none.
    public var score: Double?

    public init(
        number: Int, documentName: String, chunkIndex: Int, startCharacter: Int,
        excerpt: String, characterCount: Int, score: Double? = nil
    ) {
        self.number = number
        self.documentName = documentName
        self.chunkIndex = chunkIndex
        self.startCharacter = startCharacter
        self.excerpt = excerpt
        self.characterCount = characterCount
        self.score = score
    }

    public init(_ passage: RetrievedPassage) {
        self.init(
            number: passage.number,
            documentName: passage.documentName,
            chunkIndex: passage.chunkIndex,
            startCharacter: passage.startCharacter,
            excerpt: passage.excerpt,
            characterCount: passage.text.count,
            score: passage.score
        )
    }

    public var id: Int { number }

    /// The ranking number as the user reads it. BM25 is a ranking value, not a probability, so it is labelled
    /// `rank` and never dressed up as a percentage or a confidence — a bigger one means "matched higher in
    /// the ordering", which is the only claim the arithmetic supports.
    public var scoreLabel: String? {
        guard let score else { return nil }
        return "rank \(String(format: "%.2f", score))"
    }

    /// How the row and the transcript name a source: `[2] notes.md, chunk 2, from character 1600`, with the
    /// ranking number after it when the answer carries one.
    public var label: String {
        let place = "[\(number)] \(documentName), chunk \(chunkIndex + 1), from character \(startCharacter)"
        guard let scoreLabel else { return place }
        return "\(place), \(scoreLabel)"
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
