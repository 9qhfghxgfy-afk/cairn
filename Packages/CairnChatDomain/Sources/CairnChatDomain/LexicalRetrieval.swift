import Foundation

/// One chunk with the score that put it where it is.
///
/// The score is a ranking number, not a probability, and it is never presented as one: a source line shows
/// it as `rank 4.20`, which claims only that this passage matched higher than the one below it. It is kept
/// in the value so a test can assert that a better-matching chunk beat a worse one rather than asserting a
/// particular order that the arithmetic happens to produce today.
public struct ScoredChunk: Sendable, Equatable {
    public var chunk: DocumentChunk
    public var score: Double

    public init(chunk: DocumentChunk, score: Double) {
        self.chunk = chunk
        self.score = score
    }
}

/// BM25 over the chunks of the documents in one conversation.
///
/// This is Cairn's retrieval, and it is a choice, not a placeholder: a lexical index needs no model,
/// no download, no embedding service and no network, and it runs on the phone in milliseconds. An
/// embedding index would be better on paraphrase and worse on the exact words of a contract, a name or
/// a number — which is most of what a user asks about a document they attached. Nothing here can send
/// a query anywhere, which is the property `GroundingTests` asserts.
public struct LexicalIndex: Sendable, Equatable {
    /// BM25's tuning pair, at the published defaults. They are not tuned to Cairn's corpus because
    /// there is no corpus to tune against, and an invented number would be a claim. They are named on
    /// `Self` where they are used: inside an instance method a bare name reads an instance property,
    /// and these belong to the type.
    static let termSaturation: Double = 1.2
    static let lengthNormalisation: Double = 0.75

    public private(set) var chunks: [DocumentChunk]
    private var termCounts: [[String: Int]]
    private var documentLengths: [Int]
    private var averageLength: Double
    private var inverseDocumentFrequency: [String: Double]

    public init(chunks: [DocumentChunk]) {
        self.chunks = chunks
        self.termCounts = chunks.map { chunk in
            var counts: [String: Int] = [:]
            for token in TextTokenizer.lengthTokens(chunk.text) {
                counts[token, default: 0] += 1
            }
            return counts
        }
        self.documentLengths = termCounts.map { $0.values.reduce(0, +) }
        self.averageLength = documentLengths.isEmpty
            ? 0
            : Double(documentLengths.reduce(0, +)) / Double(documentLengths.count)
        self.inverseDocumentFrequency = LexicalIndex.idf(over: termCounts)
    }

    public var isEmpty: Bool { chunks.isEmpty }

    /// Ranked chunks for a question. Terms that appear in no document contribute nothing rather than
    /// making every chunk score zero, and a question with no matching term returns nothing at all —
    /// which is the honest answer, and the one that lets the UI say "your documents do not cover this".
    public func rank(_ question: String, count: Int) -> [ScoredChunk] {
        guard count > 0, !chunks.isEmpty else { return [] }
        let terms = TextTokenizer.queryTerms(question)
        guard !terms.isEmpty else { return [] }

        var scored: [ScoredChunk] = []
        for (offset, counts) in termCounts.enumerated() {
            var total = 0.0
            for term in terms {
                guard let frequency = counts[term], frequency > 0,
                      let idf = inverseDocumentFrequency[term] else { continue }
                let length = Double(documentLengths[offset])
                let norm = Self.termSaturation * (
                    (1 - Self.lengthNormalisation)
                        + Self.lengthNormalisation * length / max(averageLength, 1)
                )
                total += idf * Double(frequency) * (Self.termSaturation + 1)
                    / (Double(frequency) + norm)
            }
            if total > 0 {
                scored.append(ScoredChunk(chunk: chunks[offset], score: total))
            }
        }
        // Ties break on index order so the ranking is a function of the corpus, not of dictionary
        // ordering inside a hash.
        return scored.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.score != rhs.element.score {
                    return lhs.element.score > rhs.element.score
                }
                return lhs.offset < rhs.offset
            }
            .prefix(count)
            .map(\.element)
    }

    private static func idf(over counts: [[String: Int]]) -> [String: Double] {
        let total = Double(counts.count)
        var frequency: [String: Int] = [:]
        for document in counts {
            for term in document.keys { frequency[term, default: 0] += 1 }
        }
        var result: [String: Double] = [:]
        for (term, appearing) in frequency {
            let matches = Double(appearing)
            result[term] = log(1 + (total - matches + 0.5) / (matches + 0.5))
        }
        return result
    }
}
