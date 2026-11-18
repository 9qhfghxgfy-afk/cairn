import XCTest
@testable import CairnChatDomain

/// The drawer's actions, through the workspace — the only layer that knows which store a chat lives in.
///
/// These tests exist to keep two rules honest. A chat list is built from the **store**, not from the
/// display snapshot, and a temporary chat's "keep a copy" writes a new ordinary chat without moving the
/// ephemeral one anywhere. If either slips, the drawer starts lying about what the user has.
@MainActor
final class ChatWorkspaceChatListTests: XCTestCase {

    private func makeWorkspace(temporary: Bool = false) -> (ChatWorkspace, EphemeralStore, EphemeralStore) {
        let disk = EphemeralStore()
        let memory = EphemeralStore()
        let workspace = ChatWorkspace(
            persistentStore: disk,
            ephemeralStore: memory,
            providers: [MockStreamingProvider.instant],
            temporaryChat: temporary
        )
        return (workspace, disk, memory)
    }

    private func seed(_ store: EphemeralStore, title: String, secondsAgo: TimeInterval) throws -> Conversation {
        let stamp = Date(timeIntervalSinceNow: -secondsAgo)
        let chat = Conversation(title: title, createdAt: stamp, updatedAt: stamp)
        try store.saveConversation(chat)
        return chat
    }

    func testTheDrawerListsSavedChatsNewestFirstAndFiltersByTitle() throws {
        let (workspace, disk, _) = makeWorkspace()
        let older = try seed(disk, title: "Router firmware", secondsAgo: 3600)
        let newer = try seed(disk, title: "Garden bed", secondsAgo: 60)
        workspace.reloadConversations()

        XCTAssertEqual(workspace.chats().map { $0.id }, [newer.id, older.id])
        XCTAssertEqual(workspace.chats(matching: "router").map { $0.id }, [older.id])
        XCTAssertEqual(workspace.chats(matching: "nothing like this").count, 0)
    }

    func testATemporaryChatIsNotInTheListOfSavedChats() async throws {
        let (workspace, disk, memory) = makeWorkspace(temporary: true)
        await workspace.start()
        let live = try XCTUnwrap(workspace.session?.conversation)
        XCTAssertTrue(live.isTemporary)
        XCTAssertEqual(try memory.loadConversations().count, 1, "the temporary chat lives in memory")
        XCTAssertEqual(try disk.loadConversations().count, 0, "and nowhere else")
        XCTAssertFalse(workspace.chats().contains { $0.id == live.id })
    }

    func testARenamePersistsAndDoesNotSlideTheChatToTheTopOfTheList() throws {
        let (workspace, disk, _) = makeWorkspace()
        let old = try seed(disk, title: "untitled thread", secondsAgo: 7200)
        let recent = try seed(disk, title: "Yesterday", secondsAgo: 10)
        workspace.reloadConversations()

        workspace.rename(conversationID: old.id, to: "  Router firmware  ")

        let stored = try XCTUnwrap(disk.conversation(id: old.id))
        XCTAssertEqual(stored.title, "Router firmware")
        XCTAssertEqual(
            stored.updatedAt, old.updatedAt,
            "renaming is not visiting; the recency order the user knows must not change"
        )
        XCTAssertEqual(workspace.chats().map { $0.id }, [recent.id, old.id])
    }

    func testAnEmptyRenameIsRefusedRatherThanErasingATitle() throws {
        let (workspace, disk, _) = makeWorkspace()
        let chat = try seed(disk, title: "Keep me", secondsAgo: 5)
        workspace.reloadConversations()
        workspace.rename(conversationID: chat.id, to: "   ")
        XCTAssertEqual(try disk.conversation(id: chat.id)?.title, "Keep me")
        XCTAssertNil(workspace.lastError)
    }

    func testDuplicateCopiesTheOpenBranchAndLeavesTheOriginalTreeAlone() throws {
        let (workspace, disk, _) = makeWorkspace()
        let chatID = UUID()
        let asked = ChatNode(conversationID: chatID, parentID: nil, role: .user, text: "question")
        let first = ChatNode(conversationID: chatID, parentID: asked.id, role: .assistant, text: "open answer")
        let other = ChatNode(conversationID: chatID, parentID: asked.id, role: .assistant, text: "walked away", branchIndex: 1)
        let chat = Conversation(id: chatID, title: "Thread", activeLeafID: first.id)
        try disk.saveConversation(chat)
        for node in [asked, first, other] { try disk.saveNode(node) }
        workspace.reloadConversations()

        let copy = try XCTUnwrap(workspace.duplicate(conversationID: chatID))
        XCTAssertNotEqual(copy.id, chatID)
        let copied = try disk.nodes(conversationID: copy.id)
        XCTAssertEqual(Set(copied.map { $0.text }), ["question", "open answer"])
        XCTAssertEqual(copied.count, 2, "the branch the user walked away from stays out of the duplicate")
        XCTAssertEqual(try disk.nodes(conversationID: chatID).count, 3, "and the original keeps all of it")
        XCTAssertEqual(workspace.chats().count, 2)
    }

    func testKeepingACopyWritesAnOrdinaryChatAndLeavesTheTemporaryOneWhereItWas() async throws {
        let (workspace, disk, memory) = makeWorkspace(temporary: true)
        await workspace.start()
        let session = try XCTUnwrap(workspace.session)
        session.send("a temporary question")
        await SessionHarness.settle(session)
        let live = try XCTUnwrap(workspace.session?.conversation)

        let saved = try XCTUnwrap(workspace.keepCopyOfCurrentChat())
        XCTAssertFalse(saved.isTemporary, "the copy is a chat the user can come back to")
        XCTAssertNotEqual(saved.id, live.id)
        XCTAssertEqual(saved.title, "\(live.title) (copy)")

        let copyNodes = try disk.nodes(conversationID: saved.id)
        XCTAssertEqual(Set(copyNodes.map { $0.role }), [.user, .assistant])
        XCTAssertTrue(try XCTUnwrap(disk.conversation(id: saved.id)).isTemporary == false)

        // Nothing moved: the ephemeral chat is still in memory, still temporary, and still what is open.
        XCTAssertEqual(workspace.session?.conversation.id, live.id)
        XCTAssertTrue(workspace.temporaryChat)
        XCTAssertEqual(try memory.nodes(conversationID: live.id).count, copyNodes.count)
        XCTAssertEqual(try memory.loadConversations().first?.isTemporary, true)
        // The drawer now shows the copy, because the list is read back from the store.
        XCTAssertEqual(workspace.chats().map { $0.id }, [saved.id])
    }

    func testKeepingACopyIsRefusedWhenThereIsNoTemporaryChat() async throws {
        let (workspace, disk, _) = makeWorkspace()
        await workspace.start()
        let session = try XCTUnwrap(workspace.session)
        session.send("an ordinary question")
        await SessionHarness.settle(session)

        XCTAssertNil(workspace.keepCopyOfCurrentChat(), "there is nothing at risk of being lost here")
        XCTAssertEqual(try disk.nodes(conversationID: session.conversation.id).count, 2, "and nothing was copied")
    }
}

