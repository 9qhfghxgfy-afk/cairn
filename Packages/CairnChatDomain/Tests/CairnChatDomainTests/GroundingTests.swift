import XCTest
@testable import CairnChatDomain

/// Reading the documents of a conversation on this device and choosing the passages that answer the
/// question being asked.
///
/// The two properties under test are the ones a user can check: the corpus is the **path** they are
/// looking at — not every branch in the tree — and every passage that did not fit is counted rather than
/// quietly left out.
final class GroundingTests: XCTestCase {
    private let conversationID = UUID()

    private func document(_ name: String, _ text: String, id: UUID = UUID()) -> ChatAttachment {
        ChatAttachment.document(payload: Data(text.utf8), name: name, text: text)
    }

    /// A root-to-leaf path: user message, assistant reply, user message, …
    private func path(_ entries: [(String, [ChatAttachment])]) -> [ChatNode] {
        var nodes: [ChatNode] = []
        var leaf: UUID?
        for (index, entry) in entries.enumerated() {
            let added = ChatTree.append(
                to: nodes,
                conversationID: conversationID,
                parentID: leaf,
                role: index.isMultiple(of: 2) ? .user : .assistant,
                text: entry.0,
                attachments: entry.1
            )
            nodes = added.nodes
            leaf = added.node.id
        }
        return nodes
    }

    private let pumpText = """
        The impeller seal must be replaced every 4000 hours.
        Wire the motor to a dedicated 20 amp breaker.
        """

    func testADocumentAttachedEarlierIsStillInTheCorpus() {
        let nodes = path([
            ("about the pump", [document("pump-manual.txt", pumpText)]),
            ("Noted.", []),
            ("what breaker does the motor need", []),
        ])
        let outcome = Grounding.outcome(for: nodes, windowTokens: 4_000)
        XCTAssertEqual(outcome.documentsConsidered, 1)
        XCTAssertFalse(outcome.passages.isEmpty)
        XCTAssertTrue(outcome.passages.contains { $0.text.contains("20 amp") })
    }

    func testTwoFilesWithTheSameNameCountAsTwoDocuments() {
        let nodes = path([
            ("two notes", [
                document("notes.txt", "Breaker sizes for the workshop.", id: UUID()),
                document("notes.txt", "Impeller seal intervals.", id: UUID()),
            ]),
        ])
        XCTAssertEqual(Grounding.corpus(from: nodes).documentCount, 2)
        XCTAssertEqual(Grounding.outcome(for: nodes, windowTokens: 4_000).documentsConsidered, 2)
    }

    func testPassagesAreNumberedFromOneAndTheCitationsMatchThemExactly() {
        let text = (1...60).map {
            "Section \($0) covers the valve of the \($0 % 3 == 0 ? "pump" : "motor") assembly."
        }.joined(separator: "\n")
        let nodes = path([("the valve", [document("valve.txt", text)])])
        let outcome = Grounding.ground(
            question: "valve pump",
            corpus: Grounding.corpus(from: nodes),
            budget: GroundingBudget(characterCount: 2_000, passageCount: 4)
        )
        XCTAssertGreaterThan(outcome.passages.count, 1)
        XCTAssertEqual(outcome.passages.map(\.number), Array(1...outcome.passages.count))
        XCTAssertEqual(outcome.citations.count, outcome.passages.count)
        for pair in zip(outcome.citations, outcome.passages) {
            XCTAssertEqual(pair.0.number, pair.1.number)
            XCTAssertEqual(pair.0.documentName, pair.1.documentName)
            XCTAssertEqual(pair.0.startCharacter, pair.1.startCharacter)
            XCTAssertEqual(pair.0.characterCount, pair.1.text.count)
        }
    }

    func testPassagesThatDidNotFitTheBudgetAreCountedRatherThanSilentlyLeftOut() {
        let text = (1...200).map {
            "valve \($0) needs a gasket and a torque wrench for the housing bolt"
        }.joined(separator: "\n")
        let corpus = Grounding.corpus(from: path([("valves", [document("many.txt", text)])]))
        let tight = Grounding.ground(
            question: "valve gasket", corpus: corpus,
            budget: GroundingBudget(characterCount: 600, passageCount: 2)
        )
        XCTAssertLessThanOrEqual(tight.passages.count, 2)
        XCTAssertGreaterThan(tight.passagesDroppedForBudget, 0)
        let loose = Grounding.ground(
            question: "valve gasket", corpus: corpus,
            budget: GroundingBudget(characterCount: 100_000, passageCount: 40)
        )
        XCTAssertGreaterThan(loose.passages.count, tight.passages.count)
        XCTAssertEqual(loose.passagesDroppedForBudget, 0)
    }

    func testAQuestionTheDocumentsDoNotAnswerLeavesTheFileCountStandingAlone() {
        // The block still has to say a document is here — that is what makes the model say "the documents
        // do not cover this" instead of answering from memory and citing nothing.
        let nodes = path([("the pump", [document("pump.txt", pumpText)])])
        let unrelated = Grounding.ground(
            question: "how far is the moon", corpus: Grounding.corpus(from: nodes)
        )
        XCTAssertTrue(unrelated.passages.isEmpty)
        XCTAssertEqual(unrelated.documentsConsidered, 1)
        XCTAssertTrue(Grounding.outcome(for: nodes, windowTokens: 4_000).hasGrounding)
    }

    func testADocumentOnABranchTheUserIsNotLookingAtIsNotSearched() {
        // Two sibling questions under one root, each with its own file. The path the user is on carries one
        // of them; a passage from the other would steer this answer from a conversation they left.
        var nodes: [ChatNode] = []
        let root = ChatTree.append(
            to: nodes, conversationID: conversationID, parentID: nil, role: .user, text: "start"
        )
        nodes = root.nodes
        let kept = ChatTree.append(
            to: nodes, conversationID: conversationID, parentID: root.node.id, role: .user,
            text: "what breaker", attachments: [document("pump.txt", pumpText)]
        )
        nodes = kept.nodes
        let other = ChatTree.append(
            to: nodes, conversationID: conversationID, parentID: root.node.id, role: .user,
            text: "off topic",
            attachments: [document("sourdough.txt", "Feed the starter twice a day at 24 degrees.")]
        )
        nodes = other.nodes

        let onPath = ChatTree.visiblePath(nodes: nodes, activeLeafID: kept.node.id)
        let outcome = Grounding.outcome(for: onPath, windowTokens: 4_000)
        XCTAssertEqual(outcome.documentsConsidered, 1)
        XCTAssertTrue(
            outcome.passages.allSatisfy { $0.documentName == "pump.txt" },
            "a passage from the branch the user is not on reached the prompt"
        )
    }

    func testTheQuestionIsTheNewestUserMessageAndNotAnOlderOne() {
        let nodes = path([
            ("first question", []),
            ("answer", []),
            ("second question", [document("d.txt", "the second question is discussed here")]),
        ])
        XCTAssertEqual(Grounding.question(in: nodes), "second question")
    }

    func testTheSameConversationGroundsTheSameWayEveryTime() {
        let nodes = path([
            ("breaker size", [document("wiring.txt", "20 amp for the motor, 30 amp for the kiln")]),
        ])
        XCTAssertEqual(
            Grounding.outcome(for: nodes, windowTokens: 4_000),
            Grounding.outcome(for: nodes, windowTokens: 4_000)
        )
    }

    func testAnEmptyConversationGroundsNothingAndSaysSo() {
        let outcome = Grounding.outcome(for: [], windowTokens: 4_000)
        XCTAssertEqual(outcome, .empty)
        XCTAssertFalse(outcome.hasGrounding)
        XCTAssertEqual(Grounding.question(in: []), "")
    }
}
