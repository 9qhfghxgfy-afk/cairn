import Foundation

/// One piece of one document, addressable on its own.
///
/// `startCharacter` is where the piece was cut from the document as stored, so a citation can name the
/// place it came from and a user can find it in their own file. The id is derived rather than random:
/// the same document chunked twice must produce the same ids, or a citation would point somewhere else
/// after a relaunch.
public struct DocumentChunk: Sendable, Equatable, Identifiable {
    public var id: String
    public var documentID: UUID
    public var documentName: String
    public var index: Int
    public var text: String
    public var startCharacter: Int

    public init(
        documentID: UUID, documentName: String, index: Int, text: String, startCharacter: Int
    ) {
        self.id = "\(documentID.uuidString)#\(index)"
        self.documentID = documentID
        self.documentName = documentName
        self.index = index
        self.text = text
        self.startCharacter = startCharacter
    }
}

/// Cuts a document into retrieval-sized pieces without cutting a sentence in half if it can help it.
///
/// Two properties hold, and both are tested: the same text always yields the same chunks, and every
/// character of the document appears in at least one chunk. Overlap is deliberate — a sentence split
/// across a cut is still findable from the side that quotes it — and it is bounded, because overlapped
/// text is text paid for twice in a prompt.
public enum DocumentChunker {
    /// A chunk's target size in characters. Roughly a kilobyte and a half of prose: large enough to
    /// hold a paragraph with its context, small enough that several fit in a turn's passage budget.
    public static let defaultCharacterCount = 1_600
    /// How far back the next chunk starts. A fifth of a chunk, and never more than a quarter of one.
    public static let defaultOverlapCharacters = 200
    /// A chunk shorter than this is not worth citing, so a small document stays one chunk.
    public static let minimumCharacterCount = 200

    public static func chunks(
        _ text: String,
        documentID: UUID,
        documentName: String,
        characterCount: Int = DocumentChunker.defaultCharacterCount,
        overlap: Int = DocumentChunker.defaultOverlapCharacters
    ) -> [DocumentChunk] {
        let characters = Array(text)
        guard !characters.isEmpty else { return [] }
        let size = max(minimumCharacterCount, characterCount)
        let back = min(max(0, overlap), size / 4)

        var pieces: [(start: Int, end: Int)] = []
        var start = 0
        while start < characters.count {
            let hardEnd = min(start + size, characters.count)
            let end = hardEnd >= characters.count
                ? characters.count
                : boundary(in: characters, proposed: hardEnd, noEarlierThan: start + size / 2)
            pieces.append((start, end))
            if end >= characters.count { break }
            start = max(end - back, start + 1)
        }
        return pieces.enumerated().map { offset, piece in
            DocumentChunk(
                documentID: documentID,
                documentName: documentName,
                index: offset,
                text: String(characters[piece.start..<piece.end]),
                startCharacter: piece.start
            )
        }
    }

    /// Walks back from the proposed cut for a paragraph end, then a sentence end, then a word end —
    /// never further back than half a chunk, so a document of one enormous paragraph still advances.
    static func boundary(
        in characters: [Character], proposed: Int, noEarlierThan: Int
    ) -> Int {
        let searchBack = min((proposed - noEarlierThan), characters.count / 5 + 1)
        let floor = proposed - searchBack
        guard floor >= 0 else { return proposed }
        var cursor = proposed - 1
        while cursor >= floor {
            if characters[cursor] == "\n" { return cursor + 1 }
            cursor -= 1
        }
        cursor = proposed - 1
        while cursor >= floor {
            if characters[cursor] == " " { return cursor + 1 }
            cursor -= 1
        }
        return proposed
    }
}
