import XCTest
import CairnChatDomain
import CairnPersistence

/// Runs on the simulator in CI: proves the parent-linked tree survives real SwiftData
/// writes and that the on-disk store refuses temporary conversations.
@MainActor
final class SwiftDataStoreTests: XCTestCase {

    private func makeStore() throws -> SwiftDataStore {
        try SwiftDataStore(inMemory: true)
    }

    func testTreeRoundTripsThroughParentPointers() throws {
        let store = try makeStore()
        let conversation = try store.createConversation(
            title: "Trail notes", mode: .onDeviceOnly, config: .default, isTemporary: false
        )
        XCTAssertTrue(try store.nodes(conversationID: conversation.id).isEmpty)

        let user = ChatTree.append(to: [], conversationID: conversation.id, parentID: nil, role: .user, text: "first")
        try store.saveNode(user.node)

        let answerOne = ChatTree.append(
            to: user.nodes, conversationID: conversation.id, parentID: user.node.id, role: .assistant, text: "answer one"
        )
        try store.saveNode(answerOne.node)

        let answerTwo = ChatTree.append(
            to: answerOne.nodes, conversationID: conversation.id, parentID: user.node.id, role: .assistant, text: "answer two"
        )
        try store.saveNode(answerTwo.node)

        var updated = conversation
        updated.activeLeafID = answerTwo.node.id
        try store.saveConversation(updated)

        // Read back what is actually stored, not the in-memory arrays.
        let stored = try store.nodes(conversationID: conversation.id)
        XCTAssertEqual(stored.count, 3)
        XCTAssertEqual(
            ChatTree.visiblePath(nodes: stored, activeLeafID: updated.activeLeafID).map(\.text),
            ["first", "answer two"]
        )
        XCTAssertEqual(
            ChatTree.visiblePath(nodes: stored, activeLeafID: answerOne.node.id).map(\.text),
            ["first", "answer one"]
        )
        XCTAssertNil(stored.first(where: { $0.id == user.node.id })?.parentID, "a root keeps a nil parent")
        XCTAssertEqual(stored.first(where: { $0.id == user.node.id })?.branchIndex, 0)
    }

    func testRegenerateAddsASiblingRowInsteadOfOverwriting() throws {
        let store = try makeStore()
        let conversation = try store.createConversation(
            title: "Regen", mode: .onDeviceOnly, config: .default, isTemporary: false
        )
        let user = ChatTree.append(to: [], conversationID: conversation.id, parentID: nil, role: .user, text: "ask")
        try store.saveNode(user.node)
        let first = ChatTree.append(
            to: user.nodes, conversationID: conversation.id, parentID: user.node.id, role: .assistant, text: "v1"
        )
        try store.saveNode(first.node)

        guard let regen = ChatTree.regenerate(
            nodes: first.nodes, assistantNodeID: first.node.id, providerID: "mock", modelID: "cairn-mock-8b"
        ) else { return XCTFail("regenerate returned nil") }
        try store.saveNode(regen.node)

        let stored = try store.nodes(conversationID: conversation.id)
        XCTAssertEqual(stored.count, 3, "regenerate appends a row; it must not replace")
        XCTAssertEqual(stored.filter { $0.role == .assistant }.count, 2)
        XCTAssertEqual(stored.first { $0.id == first.node.id }?.text, "v1")
        XCTAssertEqual(ChatTree.children(of: user.node.id, in: stored).count, 2)
    }

    func testStreamingUpdateTouchesOneRowNotMany() throws {
        let store = try makeStore()
        let conversation = try store.createConversation(
            title: "Stream", mode: .onDeviceOnly, config: .default, isTemporary: false
        )
        let partial = ChatNode(
            conversationID: conversation.id, parentID: nil, role: .assistant,
            text: "par", state: .streaming, branchIndex: 0
        )
        try store.saveNode(partial)
        try store.saveNode(partial)

        var completed = partial
        completed.text = "partial answer"
        completed.state = .complete
        completed.metrics = GenerationMetrics(tokensGenerated: 4, elapsedSeconds: 2.0, finishReason: .stop)
        try store.saveNode(completed)

        let stored = try store.nodes(conversationID: conversation.id)
        XCTAssertEqual(stored.count, 1, "an update must land on the same row")
        XCTAssertEqual(stored.first?.text, "partial answer")
        XCTAssertEqual(stored.first?.state, .complete)
        XCTAssertEqual(stored.first?.metrics?.tokensGenerated, 4, "metrics survive the round trip")
    }

    func testOnDiskStoreRefusesTemporaryConversations() throws {
        let store = try makeStore()
        XCTAssertThrowsError(
            try store.createConversation(title: "temp", mode: .onDeviceOnly, config: .default, isTemporary: true)
        )
        let existing = try store.createConversation(
            title: "saved", mode: .onDeviceOnly, config: .default, isTemporary: false
        )
        var asTemporary = existing
        asTemporary.isTemporary = true
        XCTAssertThrowsError(try store.saveConversation(asTemporary))
    }
}
