import XCTest
@testable import CairnChatDomain

/// Copying a chat, in the two ways that mean different things.
///
/// "Duplicate" takes the branch you are looking at, because that is the conversation you had. "Keep a
/// copy" takes the whole tree, because the tree is the only thing a temporary chat will ever have - once
/// the app closes, an untaken branch is gone, and a copy that quietly dropped it would be a smaller chat
/// than the one being saved.
final class ChatDuplicationTests: XCTestCase {

    /// root <- u1 <- first answer (branch 0) <- follow up <- follow-up answer, with a second answer
    /// (branch 1) hanging off u1 that the open path does not take.
    private struct Fixture {
        let chat: Conversation
        let nodes: [ChatNode]
    }

    private func fixture() -> Fixture {
        let chatID = UUID()
        let root = ChatNode(conversationID: chatID, parentID: nil, role: .user, text: "root")
        let asked = ChatNode(conversationID: chatID, parentID: root.id, role: .user, text: "first question")
        let first = ChatNode(conversationID: chatID, parentID: asked.id, role: .assistant, text: "first answer")
        let other = ChatNode(conversationID: chatID, parentID: asked.id, role: .assistant, text: "other answer", branchIndex: 1)
        let follow = ChatNode(conversationID: chatID, parentID: first.id, role: .user, text: "follow up")
        let answered = ChatNode(conversationID: chatID, parentID: follow.id, role: .assistant, text: "follow-up answer")
        let chat = Conversation(id: chatID, title: "Fixture", activeLeafID: answered.id, isTemporary: true)
        return Fixture(chat: chat, nodes: [root, asked, first, other, follow, answered])
    }

    func testDuplicateTakesTheOpenBranchAndNothingElse() {
        let source = fixture()
        let copy = ChatDuplication.upToCurrentBranch(source.chat, nodes: source.nodes)
        XCTAssertEqual(Set(copy.nodes.map(\.text)), [
            "root", "first question", "first answer", "follow up", "follow-up answer",
        ])
        // The copy is a chat in its own right: its own id, its own title, and its leaf pointer moved with
        // the path it kept.
        XCTAssertNotEqual(copy.conversation.id, source.chat.id)
        XCTAssertEqual(copy.conversation.title, "Fixture (copy)")
        XCTAssertEqual(copy.nodes.last?.text, "follow-up answer")
        XCTAssertEqual(copy.conversation.activeLeafID, copy.nodes.last?.id)
        // Temporary stays temporary: copying a chat is not the app deciding it may now be written to disk.
        XCTAssertEqual(copy.conversation.isTemporary, source.chat.isTemporary)
    }

    func testKeepACopyCarriesEveryBranch() {
        let source = fixture()
        let copy = ChatDuplication.entireChat(source.chat, nodes: source.nodes)
        XCTAssertEqual(copy.nodes.count, source.nodes.count)
        XCTAssertTrue(copy.nodes.contains { $0.text == "other answer" })
    }

    func testEveryIDDiffersAndNoParentIsLeftPointingAtTheOriginalTree() {
        let source = fixture()
        for copy in [
            ChatDuplication.upToCurrentBranch(source.chat, nodes: source.nodes),
            ChatDuplication.entireChat(source.chat, nodes: source.nodes),
        ] {
            let originalIDs = Set(source.nodes.map(\.id))
            XCTAssertFalse(copy.nodes.contains { originalIDs.contains($0.id) })
            let copyIDs = Set(copy.nodes.map(\.id))
            XCTAssertFalse(copy.nodes.contains { $0.parentID != nil && !copyIDs.contains($0.parentID!) })
            XCTAssertTrue(copy.nodes.allSatisfy { $0.conversationID == copy.conversation.id })
        }
    }

    func testBranchIndexAndTimestampsSurviveAndParentsStillPrecedeChildren() {
        let source = fixture()
        let copy = ChatDuplication.entireChat(source.chat, nodes: source.nodes)
        let byText = Dictionary(uniqueKeysWithValues: copy.nodes.map { ($0.text, $0) })
        let originals = Dictionary(uniqueKeysWithValues: source.nodes.map { ($0.text, $0) })
        XCTAssertEqual(byText["other answer"]?.branchIndex, originals["other answer"]?.branchIndex)
        XCTAssertEqual(copy.nodes.map { $0.createdAt }, source.nodes.map { $0.createdAt })
        for (index, node) in copy.nodes.enumerated() {
            guard let parentID = node.parentID else { continue }
            XCTAssertTrue(copy.nodes[0..<index].contains { $0.id == parentID }, "\(node.text) follows its parent")
        }
    }

    func testALeafThatPointsAtNothingStillProducesAUsableCopy() {
        // A conversation whose leaf pointer is stale must still copy whole rather than come back empty,
        // because an empty copy of a real chat is the worst possible outcome.
        let source = fixture()
        let stale = Conversation(id: source.chat.id, title: source.chat.title, activeLeafID: UUID())
        let copy = ChatDuplication.upToCurrentBranch(stale, nodes: source.nodes)
        XCTAssertEqual(copy.nodes.count, source.nodes.count)
        XCTAssertEqual(copy.conversation.activeLeafID, copy.nodes.last?.id)
    }

    func testMessagesFromAnotherChatAreNotCarriedIn() {
        let source = fixture()
        let stranger = ChatNode(conversationID: UUID(), parentID: nil, role: .user, text: "someone else's chat")
        let copy = ChatDuplication.entireChat(source.chat, nodes: source.nodes + [stranger])
        XCTAssertFalse(copy.nodes.contains { $0.text == "someone else's chat" })
    }
}
