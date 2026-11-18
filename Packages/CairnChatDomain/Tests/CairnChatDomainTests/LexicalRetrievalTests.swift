import XCTest
@testable import CairnChatDomain

/// BM25 over document chunks, on this device.
///
/// The behaviour that matters here is honest retrieval, not cleverness: a question the documents do not
/// answer must come back empty rather than ranked, because a weak passage promoted to the top of a prompt
/// becomes an answer the user will trust.
final class LexicalRetrievalTests: XCTestCase {
    private let first = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000001")!
    private let second = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000002")!

    private func chunk(
        _ documentID: UUID, _ name: String, _ index: Int, _ text: String
    ) -> DocumentChunk {
        DocumentChunk(documentID: documentID, documentName: name, index: index, text: text, startCharacter: index * 100)
    }

    private var corpus: DocumentCorpus {
        DocumentCorpus(chunks: [
            chunk(first, "pump-manual.txt", 0, "The impeller seal must be replaced every 4000 hours."),
            chunk(first, "pump-manual.txt", 1, "Wire the motor to a dedicated 20 amp breaker."),
            chunk(second, "wiring.txt", 0, "Breaker sizes for the workshop: 20 amp, 30 amp, 60 amp."),
        ])
    }

    func testTheChunkThatAnswersRanksFirst() {
        let ranked = LexicalIndex(chunks: corpus.chunks).rank("what amp breaker for the motor", count: 3)
        XCTAssertFalse(ranked.isEmpty)
        XCTAssertEqual(ranked.first?.chunk.documentName, "pump-manual.txt")
        XCTAssertEqual(ranked.first?.chunk.index, 1)
    }

    func testAQuestionTheDocumentsDoNotCoverReturnsNothingRatherThanTheBestItHas() {
        let ranked = LexicalIndex(chunks: corpus.chunks).rank("how do I bake sourdough", count: 3)
        XCTAssertTrue(ranked.isEmpty, "an unrelated question must not be answered with an unrelated passage")
    }

    func testAQuestionOfOnlyStopWordsReturnsNothing() {
        XCTAssertTrue(
            LexicalIndex(chunks: corpus.chunks).rank("the and of a to", count: 3).isEmpty
        )
    }

    func testARarerTermOutweighsAFrequentOne() {
        let id = first
        let chunks = [
            chunk(id, "a.txt", 0, "impeller impeller impeller impeller impeller impeller impeller"),
            chunk(id, "b.txt", 0, "impeller and the word gearbox appears exactly once here"),
        ]
        let ranked = LexicalIndex(chunks: chunks).rank("gearbox impeller", count: 2)
        XCTAssertEqual(ranked.count, 2)
        // Both mention impeller often; only one mentions the rarer word at all, and that one must lead.
        XCTAssertEqual(ranked.first?.chunk.text.contains("gearbox"), true)
    }

    func testRankingIsStableForTheSameCorpus() {
        let index = LexicalIndex(chunks: corpus.chunks)
        XCTAssertEqual(index.rank("breaker amp motor", count: 3), index.rank("breaker amp motor", count: 3))
    }

    func testCountCapsTheResultAndNeverReturnsMoreThanAskedFor() {
        XCTAssertEqual(LexicalIndex(chunks: corpus.chunks).rank("breaker", count: 1).count, 1)
        XCTAssertEqual(LexicalIndex(chunks: corpus.chunks).rank("breaker", count: 0).count, 0)
    }

    func testOneTokeniserServesBothTheIndexAndTheQuestion() {
        // A query tokenised differently from the documents is a retrieval miss that reads as "no answer".
        XCTAssertTrue(TextTokenizer.queryTerms("What AMP breaker?").contains("breaker"))
        XCTAssertEqual(TextTokenizer.queryTerms("impeller impeller seal"), ["impeller", "seal"])
        XCTAssertTrue(TextTokenizer.lengthTokens("the impeller").count > TextTokenizer.contentTokens("the impeller").count)
    }

    func testExcerptsAreBoundedSoASourceLineStaysALine() {
        let long = String(repeating: "clause ", count: 200)
        let excerpt = PassageExcerpt.of(long)
        XCTAssertLessThanOrEqual(excerpt.count, PassageExcerpt.characterCount + 1)
        XCTAssertTrue(excerpt.hasSuffix("…"))
        XCTAssertFalse(PassageExcerpt.of("a line\nbroken in two").contains("\n"))
    }
}
