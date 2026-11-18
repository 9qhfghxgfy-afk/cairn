import Foundation

/// Every chunk of every document a conversation carries, in the order the conversation meets them.
public struct DocumentCorpus: Sendable, Equatable {
    public var chunks: [DocumentChunk]

    public init(chunks: [DocumentChunk] = []) {
        self.chunks = chunks
    }

    public static let empty = DocumentCorpus()

    public var isEmpty: Bool { chunks.isEmpty }

    /// Distinct documents, counted by attachment id rather than by name: two files called `notes.txt`
    /// attached to different turns are two documents, and a claim about "1 document" that merges them
    /// would be wrong out loud.
    public var documentIDs: [UUID] {
        var seen = Set<UUID>()
        var ids: [UUID] = []
        for chunk in chunks where !seen.contains(chunk.documentID) {
            seen.insert(chunk.documentID)
            ids.append(chunk.documentID)
        }
        return ids
    }

    public var documentCount: Int { documentIDs.count }
}

/// How much of a turn's prompt the retrieved passages may take.
///
/// The budget is fitted to the context window the user configured, because passages that crowd out the
/// conversation are worse than fewer passages. With no configured window the app does not know the
/// server's size, so it takes a modest standing share rather than guessing at a big one.
public struct GroundingBudget: Sendable, Equatable {
    public var characterCount: Int
    public var passageCount: Int

    public init(characterCount: Int, passageCount: Int) {
        self.characterCount = characterCount
        self.passageCount = passageCount
    }

    public static let standard = GroundingBudget(characterCount: 4_000, passageCount: 6)
    /// Never a token of the prompt for passages, whatever the window says.
    public static let floorCharacterCount = 800
    /// A 256K window does not make it right to paste 200K of a document into every turn.
    public static let ceilingCharacterCount = 8_000

    /// A token is about four characters; a quarter of the window goes to passages, which leaves the
    /// conversation, the persona and the answer three quarters of it.
    public static func fitted(toContextWindow tokens: Int?) -> GroundingBudget {
        guard let tokens, tokens > 0 else { return standard }
        let characters = min(
            ceilingCharacterCount,
            max(floorCharacterCount, tokens)
        )
        return GroundingBudget(characterCount: characters, passageCount: standard.passageCount)
    }
}

/// What grounding produced for one turn: the passages that go into the prompt, and the sources the
/// answer will be credited with.
public struct GroundingOutcome: Sendable, Equatable {
    public var passages: [RetrievedPassage]
    public var citations: [SourceCitation]
    /// Documents that were searched, whether or not any of their passages were used. This is the
    /// number the injected block reports, and it must be the one the user actually attached.
    public var documentsConsidered: Int
    /// Passages that ranked in but did not fit the budget. Said out loud in the sheet rather than
    /// quietly dropped.
    public var passagesDroppedForBudget: Int

    public init(
        passages: [RetrievedPassage] = [],
        citations: [SourceCitation] = [],
        documentsConsidered: Int = 0,
        passagesDroppedForBudget: Int = 0
    ) {
        self.passages = passages
        self.citations = citations
        self.documentsConsidered = documentsConsidered
        self.passagesDroppedForBudget = passagesDroppedForBudget
    }

    public static let empty = GroundingOutcome()

    public var isEmpty: Bool { passages.isEmpty }

    public var hasGrounding: Bool { documentsConsidered > 0 || !passages.isEmpty }
}
