import XCTest
@testable import CairnChatDomain

/// The Markdown copy of a chat — the one a person reads, not the one an app re-imports.
///
/// Two things matter here. The untaken branches are still in the file, because they are the user's
/// answers too; and reasoning appears only when a backend actually sent it, quoted as it arrived. A
/// transcript that dropped the branches or paraphrased the thinking would rewrite the conversation on the
/// way out.
final class ChatTranscriptTests: XCTestCase {

    private func fixture() -> (Conversation, [ChatNode]) {
        let chatID = UUID()
        let asked = ChatNode(conversationID: chatID, parentID: nil, role: .user, text: "why is my lan slow?")
        let first = ChatNode(
            conversationID: chatID, parentID: asked.id, role: .assistant, text: "Check the cable first.",
            thinking: "Two candidates: cable, then duplex."
        )
        let other = ChatNode(conversationID: chatID, parentID: asked.id, role: .assistant, text: "Maybe the driver.", branchIndex: 1)
        let chat = Conversation(id: chatID, title: "Slow LAN", activeLeafID: first.id)
        return (chat, [asked, first, other])
    }

    func testTheOpenPathComesFirstAndTheUntakenAnswerIsStillInk() {
        let (chat, nodes) = fixture()
        let page = ChatTranscript.markdown(conversation: chat, nodes: nodes, exportedAt: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertTrue(page.hasPrefix("# Slow LAN"))
        XCTAssertTrue(page.contains("Check the cable first."))
        XCTAssertTrue(page.contains("Answers on other branches"))
        XCTAssertTrue(page.contains("Maybe the driver."))
        XCTAssertTrue(page.range(of: "Check the cable first.")!.lowerBound < page.range(of: "Maybe the driver.")!.lowerBound)
    }

    func testReasoningIsQuotedOnlyWhenABackendSentItAndNeverInvented() {
        let (chat, nodes) = fixture()
        let page = ChatTranscript.markdown(conversation: chat, nodes: nodes)
        XCTAssertTrue(page.contains("Reasoning, as the model sent it"))
        XCTAssertTrue(page.contains("> Two candidates: cable, then duplex."))

        let silent = nodes.map { var copy = $0; copy.thinking = nil; return copy }
        let quiet = ChatTranscript.markdown(conversation: chat, nodes: silent)
        XCTAssertFalse(quiet.contains("Reasoning"))
    }

    func testAStoppedAnswerSaysItWasStoppedRatherThanReadingAsFinished() {
        let (chat, nodes) = fixture()
        var cut = nodes
        cut[1].state = .cancelled
        let page = ChatTranscript.markdown(conversation: chat, nodes: cut)
        XCTAssertTrue(page.contains("stopped by the user"))
    }

    func testAChatWithNoLeafPointerStillExportsItsMessages() {
        let (chat, nodes) = fixture()
        let unpointed = Conversation(id: chat.id, title: chat.title, activeLeafID: nil)
        let page = ChatTranscript.markdown(conversation: unpointed, nodes: nodes)
        XCTAssertTrue(page.contains("why is my lan slow?"))
        XCTAssertTrue(page.contains("Check the cable first."))
    }

    func testSeveralChatsInOneDocumentStayApart() {
        let (first, firstNodes) = fixture()
        let secondID = UUID()
        let asked = ChatNode(conversationID: secondID, parentID: nil, role: .user, text: "second chat question")
        let second = Conversation(id: secondID, title: "Second chat", activeLeafID: asked.id)
        let page = ChatTranscript.markdown(conversations: [first, second], nodes: firstNodes + [asked])
        XCTAssertTrue(page.contains("# Slow LAN"))
        XCTAssertTrue(page.contains("# Second chat"))
        XCTAssertTrue(page.contains("\n---\n"))
    }
}
