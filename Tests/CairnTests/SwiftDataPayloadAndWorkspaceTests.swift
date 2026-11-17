import XCTest
import CairnChatDomain
import CairnPersistence

@MainActor
final class SwiftDataPayloadTests: XCTestCase {

    func testThinkingAndCandidateDraftsSurviveTheRoundTrip() throws {
        let store = try SwiftDataStore(inMemory: true)
        let conversation = try store.createConversation(
            title: "Synth", mode: .hybridSynthesized, config: .default, isTemporary: false
        )
        let node = ChatNode(
            conversationID: conversation.id, parentID: nil, role: .assistant,
            kind: .synthesized, text: "unified answer", thinking: "compared both drafts",
            state: .complete, branchIndex: 0,
            drafts: [
                CandidateDraft(order: 0, sourceLabel: "On-device", providerID: "device", modelID: "fm", text: "a"),
                CandidateDraft(order: 1, sourceLabel: "Remote", providerID: "ollama", modelID: "qwen3:8b", text: "b"),
            ]
        )
        try store.saveNode(node)

        let stored = try store.nodes(conversationID: conversation.id).first
        XCTAssertEqual(stored?.kind, .synthesized)
        XCTAssertEqual(stored?.thinking, "compared both drafts")
        XCTAssertEqual(stored?.drafts.count, 2)
        XCTAssertEqual(stored?.drafts.map(\.sourceLabel), ["On-device", "Remote"])
    }

    func testDeleteConversationClearsItsNodes() throws {
        let store = try SwiftDataStore(inMemory: true)
        let conversation = try store.createConversation(
            title: "Delete me", mode: .onDeviceOnly, config: .default, isTemporary: false
        )
        let node = ChatTree.append(to: [], conversationID: conversation.id, parentID: nil, role: .user, text: "x")
        try store.saveNode(node.node)
        XCTAssertEqual(try store.nodes(conversationID: conversation.id).count, 1)

        try store.deleteConversation(id: conversation.id)
        XCTAssertEqual(try store.nodes(conversationID: conversation.id).count, 0)
        XCTAssertNil(try store.conversation(id: conversation.id))
    }
}

/// Workspace wiring: a persisted workspace backed by SwiftData plus the mock engine.
@MainActor
final class WorkspaceTests: XCTestCase {

    func testWorkspacePersistsAcrossASessionRebind() async throws {
        let store = try SwiftDataStore(inMemory: true)
        let workspace = ChatWorkspace(
            persistentStore: store,
            providers: [MockStreamingProvider.instant],
            mode: .onDeviceOnly,
            temporaryChat: false
        )
        await workspace.start()
        XCTAssertNotNil(workspace.session)

        workspace.session?.send("keep this")
        var ticks = 0
        while workspace.session?.isBusy == true, ticks < 200 {
            ticks += 1
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertEqual(workspace.session?.path.count, 2)

        // Rebinding to the same conversation rebuilds the path from stored rows.
        let conversationID = workspace.session!.conversation.id
        workspace.select(conversationID: conversationID)
        await workspace.session?.bootstrap()
        XCTAssertEqual(workspace.session?.path.map(\.text).first, "keep this")
        XCTAssertEqual(workspace.conversations.count, 1)
    }

    func testTogglingTemporaryChatStartsAFreshEphemeralChatWithoutTouchingDisk() async throws {
        let store = try SwiftDataStore(inMemory: true)
        let workspace = ChatWorkspace(
            persistentStore: store,
            providers: [MockStreamingProvider.instant],
            temporaryChat: false
        )
        await workspace.start()
        workspace.session?.send("saved note")
        var ticks = 0
        while workspace.session?.isBusy == true, ticks < 200 {
            ticks += 1
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        let savedCount = workspace.conversations.count

        workspace.temporaryChat = true
        await workspace.session?.bootstrap()
        XCTAssertTrue(workspace.session?.conversation.isTemporary ?? false)

        workspace.session?.send("ephemeral note")
        ticks = 0
        while workspace.session?.isBusy == true, ticks < 200 {
            ticks += 1
            try? await Task.sleep(nanoseconds: 2_000_000)
        }

        // The ephemeral chat is in memory, and the on-disk store is unchanged.
        XCTAssertEqual(workspace.session?.path.count, 2)
        XCTAssertEqual(workspace.conversations.count, savedCount)
        let persisted = try store.loadConversations()
        XCTAssertEqual(persisted.count, 1)
        let persistedNodes = try store.nodes(conversationID: persisted[0].id)
        XCTAssertTrue(persistedNodes.contains { $0.text == "saved note" })
        XCTAssertFalse(persistedNodes.contains { $0.text == "ephemeral note" })
    }
}
