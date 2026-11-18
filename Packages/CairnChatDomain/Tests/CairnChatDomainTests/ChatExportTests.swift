import XCTest
@testable import CairnChatDomain

/// A chat written out and read back.
///
/// The property that decides whether this feature is trustworthy is the first one below: a chat with
/// branches that goes out to a file and comes back must still have those branches. Everything else is a
/// refusal, and a refusal has to name the file's own value rather than guess at it — decoding a message
/// into the nearest known state would put words in a model's mouth.
final class ChatExportTests: XCTestCase {

    /// A chat with a real fork: one answer, a second answer beside it, and a continuation of the first.
    ///
    /// Timestamps are pinned to exact quarter-seconds so the round-trip assertions below compare against
    /// bytes the file can hold exactly, rather than against a `Date()` whose microseconds the format does
    /// not carry.
    private func chatWithBranches() -> (Conversation, [ChatNode]) {
        let chatID = UUID()
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        func at(_ seconds: TimeInterval) -> Date { base.addingTimeInterval(seconds) }
        let asked = ChatNode(
            conversationID: chatID, parentID: nil, role: .user,
            text: "how do I rotate a router key?", createdAt: at(0)
        )
        let first = ChatNode(
            conversationID: chatID, parentID: asked.id, role: .assistant, text: "First: drain the lease.",
            thinking: "Checking DHCP lease times.", modelID: "cairn-mock-8b", createdAt: at(0.25),
            metrics: GenerationMetrics(tokensGenerated: 12, elapsedSeconds: 2, finishReason: .length)
        )
        let other = ChatNode(
            conversationID: chatID, parentID: asked.id, role: .assistant,
            text: "Other answer.", branchIndex: 1, createdAt: at(0.5)
        )
        let follow = ChatNode(
            conversationID: chatID, parentID: first.id, role: .user, text: "and the client?", createdAt: at(0.75)
        )
        let answered = ChatNode(
            conversationID: chatID, parentID: follow.id, role: .assistant, text: "Renew it.", createdAt: at(1)
        )
        let chat = Conversation(
            id: chatID, title: "Router keys", activeLeafID: answered.id, createdAt: at(0), updatedAt: at(1)
        )
        return (chat, [asked, first, other, follow, answered])
    }

    private func askedID(of nodes: [ChatNode]) -> UUID? {
        nodes.first { $0.text == "how do I rotate a router key?" }?.id
    }

    func testRoundTripPreservesEveryBranchAndEveryField() throws {
        let (chat, nodes) = chatWithBranches()
        let data = try ChatExport.data(
            conversations: [chat], nodes: nodes, exportedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let read = try ChatImport.contents(try ChatExport.decode(data))

        XCTAssertEqual(read.conversations, [chat])
        XCTAssertEqual(Set(read.nodes.map { $0.id }), Set(nodes.map { $0.id }))
        // The fork survives: two answers under one question, each knowing its own branch index.
        let siblings = read.nodes.filter { $0.parentID == askedID(of: read.nodes) }
        XCTAssertEqual(siblings.count, 2)
        XCTAssertEqual(Set(siblings.map { $0.branchIndex }), [0, 1])
        // Fields that make an answer explainable later, not just readable now.
        let continued = read.nodes.first { $0.text == "First: drain the lease." }
        XCTAssertEqual(continued?.thinking, "Checking DHCP lease times.")
        XCTAssertEqual(continued?.modelID, "cairn-mock-8b")
        XCTAssertEqual(continued?.metrics?.finishReason, .length)
    }

    func testTheSameChatTwiceProducesTheSameBytes() throws {
        let (chat, nodes) = chatWithBranches()
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try ChatExport.data(conversations: [chat], nodes: nodes, exportedAt: stamp)
        let second = try ChatExport.data(conversations: [chat], nodes: nodes, exportedAt: stamp)
        XCTAssertEqual(first, second, "a diff should be able to answer whether the data changed")
    }
    func testAFileThatIsNotACairnChatIsNamedRatherThanHalfRead() {
        let foreign = Data(#"{"format":"someone.else","version":1,"chats":[],"nodes":[]}"#.utf8)
        XCTAssertThrowsError(try ChatExport.decode(foreign)) { issue in
            XCTAssertEqual(issue as? ChatExportIssue, .foreignFormat("someone.else"))
        }
    }

    func testANewerFileIsRefusedWithItsOwnNumber() {
        let newer = Data(#"{"format":"cairn.chat","version":2,"chats":[],"nodes":[]}"#.utf8)
        XCTAssertThrowsError(try ChatExport.decode(newer)) { issue in
            XCTAssertEqual(issue as? ChatExportIssue, .newerVersion(2))
        }
        let ancient = Data(#"{"format":"cairn.chat","version":0,"chats":[],"nodes":[]}"#.utf8)
        XCTAssertThrowsError(try ChatExport.decode(ancient)) { issue in
            XCTAssertEqual(issue as? ChatExportIssue, .unsupportedVersion(0))
        }
    }

    func testAFileWithNoMarkerIsUnreadableAndDoesNotQuoteWhatItCouldNotRead() {
        let junk = Data("top secret prompt text".utf8)
        XCTAssertThrowsError(try ChatExport.decode(junk)) { issue in
            guard case .unreadable(let reason)? = issue as? ChatExportIssue else {
                return XCTFail("expected unreadable, got \(issue)")
            }
            XCTAssertFalse(reason.contains("secret"))
        }
    }

    func testAStateThisBuildDoesNotHaveIsRefusedRatherThanRoundedToTheNearestOne() throws {
        let (chat, nodes) = chatWithBranches()
        var bundle = ChatExport.bundle(conversation: chat, nodes: nodes)
        bundle.nodes[1].state = "quantum"
        XCTAssertThrowsError(try ChatImport.contents(bundle)) { issue in
            guard case .malformed(let reason)? = issue as? ChatExportIssue else {
                return XCTFail("expected malformed, got \(issue)")
            }
            XCTAssertTrue(reason.contains("role, kind or state"))
        }
    }

    func testADuplicateIdAOrphanAndACycleAreEachRefused() throws {
        let (chat, nodes) = chatWithBranches()

        var doubled = ChatExport.bundle(conversation: chat, nodes: nodes)
        doubled.nodes.append(doubled.nodes[0])
        XCTAssertThrowsError(try ChatImport.contents(doubled), "two messages with one id")

        var orphaned = ChatExport.bundle(conversation: chat, nodes: nodes)
        orphaned.nodes[2].parentID = UUID()
        XCTAssertThrowsError(try ChatImport.contents(orphaned), "a parent that is not in the file")

        var looping = ChatExport.bundle(conversation: chat, nodes: nodes)
        let root = looping.nodes[0].id
        let tip = looping.nodes[4].id
        looping.nodes[0].parentID = tip
        looping.nodes[4].parentID = root
        XCTAssertThrowsError(try ChatImport.contents(looping), "a message that is its own ancestor")
    }

    func testReopeningTheSameFileTwiceGivesTwoChatsRatherThanOverwritingOne() throws {
        let (chat, nodes) = chatWithBranches()
        let bundle = ChatExport.bundle(conversation: chat, nodes: nodes)
        let asCopy = try ChatImport.plan(
            bundle,
            takenConversationIDs: Set([chat.id]),
            takenNodeIDs: Set(nodes.map { $0.id })
        )
        XCTAssertTrue(asCopy.assignedFreshIDs)
        XCTAssertEqual(asCopy.copiedConversationIDs, Set([asCopy.conversations[0].id]))
        XCTAssertEqual(asCopy.conversations[0].title, "Router keys (copy)")
        XCTAssertNotEqual(asCopy.conversations[0].id, chat.id)
        // The tree survives the remap: every parent is inside the copy, the chat opens at its own copy of
        // the message it was open at, and the untaken branch came along.
        XCTAssertEqual(asCopy.nodes.count, nodes.count)
        let ids = Set(asCopy.nodes.map { $0.id })
        XCTAssertFalse(asCopy.nodes.contains { $0.parentID != nil && !ids.contains($0.parentID!) })
        XCTAssertEqual(asCopy.conversations[0].activeLeafID, asCopy.nodes.last?.id)
        XCTAssertTrue(asCopy.nodes.contains { $0.branchIndex == 1 })
        for (index, node) in asCopy.nodes.enumerated() {
            guard let parentID = node.parentID else { continue }
            XCTAssertTrue(asCopy.nodes[0..<index].contains { $0.id == parentID })
        }
    }

    func testAMessageBelongingToAnotherChatIsNotSmuggledIntoTheFile() throws {
        let (chat, nodes) = chatWithBranches()
        let stranger = ChatNode(conversationID: UUID(), parentID: nil, role: .user, text: "not yours")
        let bundle = ChatExport.bundle(conversation: chat, nodes: nodes + [stranger])
        XCTAssertEqual(bundle.nodes.count, nodes.count)
    }

    func testAQuestionAndAFastAnswerInsideOneSecondKeepTheirOrder() throws {
        // A local model answers in well under a second, so a whole turn routinely lands inside one. A
        // seconds-precision timestamp would write both messages at the same instant and the file would no
        // longer say which came first.
        let chatID = UUID()
        let asked = ChatNode(
            conversationID: chatID, parentID: nil, role: .user, text: "quick one",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000.120)
        )
        let answered = ChatNode(
            conversationID: chatID, parentID: asked.id, role: .assistant, text: "done",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000.340)
        )
        let chat = Conversation(
            id: chatID, title: "Fast", activeLeafID: answered.id,
            createdAt: asked.createdAt, updatedAt: answered.createdAt
        )

        let data = try ChatExport.data(conversations: [chat], nodes: [asked, answered])
        let read = try ChatImport.contents(try ChatExport.decode(data))
        let restored = read.nodes.sorted { $0.createdAt < $1.createdAt }
        XCTAssertEqual(restored.map { $0.role }, [.user, .assistant])
        XCTAssertLessThan(restored[0].createdAt, restored[1].createdAt)
        for (written, original) in zip(restored, [asked, answered]) {
            XCTAssertLessThan(abs(written.createdAt.timeIntervalSince(original.createdAt)), 0.001)
        }
    }
}

