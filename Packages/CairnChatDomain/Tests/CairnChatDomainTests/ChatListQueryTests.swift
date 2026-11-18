import XCTest
@testable import CairnChatDomain

/// Searching and ordering the chat list.
///
/// There is no cap here to test, and that is deliberate: a chat the user made is a row, and Cairn has no
/// reason to make them delete one to add another. What is tested is that a chat is always *findable* —
/// including one whose title was never typed.
final class ChatListQueryTests: XCTestCase {

    private func chat(_ title: String, at secondsAgo: TimeInterval, temporary: Bool = false) -> Conversation {
        Conversation(
            title: title,
            createdAt: Date(timeIntervalSinceNow: -secondsAgo),
            updatedAt: Date(timeIntervalSinceNow: -secondsAgo),
            isTemporary: temporary
        )
    }

    func testNewestTouchedFirst() {
        let older = chat("older", at: 3600)
        let newer = chat("newer", at: 60)
        XCTAssertEqual(ChatListQuery.list([older, newer]).map(\.id), [newer.id, older.id])
    }

    func testAnUntitledChatIsStillFoundAndStillSorted() {
        let blank = chat("   ", at: 60)
        let results = ChatListQuery.list([blank], query: "untitled")
        XCTAssertEqual(results.map(\.id), [blank.id])
        XCTAssertEqual(ChatListQuery.visibleTitle(blank), ChatListQuery.untitledTitle)
    }

    func testSearchIgnoresCaseAndSurroundingSpace() {
        let chats = [chat("Router Firmware", at: 10), chat("Recipes", at: 20)]
        XCTAssertEqual(ChatListQuery.list(chats, query: "  router ").map(\.id), [chats[0].id])
        XCTAssertEqual(ChatListQuery.list(chats, query: "RECIPES").map(\.id), [chats[1].id])
    }

    func testAWordSplitAcrossTwoLinesStillMatches() {
        // The drawer shows the title on two lines, and a user typing what they see should get what they
        // see: a line break inside a word is not a different word.
        let chats = [chat("WireGuard\nfirmware", at: 10)]
        XCTAssertEqual(ChatListQuery.list(chats, query: "guard").map(\.id), chats.map(\.id))
    }

    func testAnEmptyQueryListsEverythingInOrder() {
        let chats = [chat("b", at: 5), chat("a", at: 50), chat("c", at: 500)]
        XCTAssertEqual(ChatListQuery.list(chats, query: "").map(\.title), ["b", "a", "c"])
    }

    func testAQueryThatMatchesNothingReturnsNothingRatherThanEverything() {
        XCTAssertEqual(ChatListQuery.list([chat("firmware", at: 1)], query: "zzz").count, 0)
    }
}
