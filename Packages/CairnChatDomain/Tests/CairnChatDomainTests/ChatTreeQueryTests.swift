import XCTest
@testable import CairnChatDomain

final class ChatTreeQueryTests: XCTestCase {

    let cid = UUID()

    /// user -> assistant(v1) + assistant(v2) -> user(next)
    private func fixture() -> (a1: ChatNode, a2: ChatNode, nodes: [ChatNode]) {
        var tree = ChatDraftTree()
        let user = tree.append(conversationID: cid, parentID: nil, role: .user, text: "ask")
        let a1 = tree.append(conversationID: cid, parentID: user.id, role: .assistant, text: "v1")
        let a2 = tree.append(conversationID: cid, parentID: user.id, role: .assistant, text: "v2")
        tree.append(conversationID: cid, parentID: a2.id, role: .user, text: "next")
        return (a1, a2, tree.nodes)
    }

    func testBranchPositionIsOneBased() {
        let f = fixture()

        let older = ChatTree.branchPosition(of: f.a1, in: f.nodes)
        XCTAssertEqual(older.index, 1)
        XCTAssertEqual(older.total, 2)
        XCTAssertFalse(older.canGoBack)
        XCTAssertTrue(older.canGoForward)

        let newer = ChatTree.branchPosition(of: f.a2, in: f.nodes)
        XCTAssertEqual(newer.index, 2)
        XCTAssertTrue(newer.canGoBack)
        XCTAssertFalse(newer.canGoForward)

        XCTAssertTrue(ChatTree.hasSiblingBranches(of: f.a1, in: f.nodes))
    }

    func testSelectSiblingClampsInsteadOfWrapping() {
        let f = fixture()
        XCTAssertNil(ChatTree.selectSibling(nodes: f.nodes, nodeID: f.a1.id, delta: -1))
        XCTAssertNil(ChatTree.selectSibling(nodes: f.nodes, nodeID: f.a2.id, delta: 1))
        XCTAssertEqual(ChatTree.selectSibling(nodes: f.nodes, nodeID: f.a2.id, delta: -1)?.id, f.a1.id)
        XCTAssertNil(ChatTree.selectSibling(nodes: f.nodes, nodeID: UUID(), delta: 1))
    }

    func testPathTerminatesOnMalformedParentCycle() {
        let a = ChatNode(conversationID: cid, parentID: nil, role: .user, text: "a")
        let b = ChatNode(conversationID: cid, parentID: a.id, role: .assistant, text: "b")
        let loopedA = ChatNode(conversationID: cid, parentID: b.id, role: .user, text: "a")

        // a -> b -> a would spin forever without the visited guard.
        let walked = ChatTree.path(fromRootToLeaf: loopedA.id, in: [loopedA, b])
        XCTAssertFalse(walked.isEmpty)
        XCTAssertLessThanOrEqual(walked.count, 2)
    }

    func testMessagesInjectSystemPromptAndSkipEmptyStreamingNodes() {
        var tree = ChatDraftTree()
        let userA = tree.append(conversationID: cid, parentID: nil, role: .user, text: "first")
        let answer = tree.append(conversationID: cid, parentID: userA.id, role: .assistant, text: "answer")
        let userB = tree.append(conversationID: cid, parentID: answer.id, role: .user, text: "next")

        var params = SamplingParams.default
        params.systemPrompt = "You are Cairn."

        let payload = ChatTree.messages(for: tree.visiblePath(activeLeafID: userB.id), params: params)
        XCTAssertEqual(payload.map(\.role), [.system, .user, .assistant, .user])
        XCTAssertEqual(payload.first?.text, "You are Cairn.")
        XCTAssertEqual(payload.count, 4)

        let streaming = ChatNode(
            conversationID: cid, parentID: userB.id, role: .assistant, text: "", state: .streaming
        )
        let withEmpty = ChatTree.messages(
            for: ChatTree.visiblePath(nodes: tree.nodes + [streaming], activeLeafID: streaming.id),
            params: params
        )
        XCTAssertEqual(withEmpty.count, 4, "an empty streaming node must not be sent to the backend")
    }

    func testSynthesizedTurnIsOneNodeCarryingItsDrafts() {
        var tree = ChatDraftTree()
        let user = tree.append(conversationID: cid, parentID: nil, role: .user, text: "compare")
        let drafts = [
            CandidateDraft(order: 0, sourceLabel: "On-device", providerID: "device", modelID: "apple-fm"),
            CandidateDraft(order: 1, sourceLabel: "Remote", providerID: "ollama", modelID: "qwen3:8b"),
        ]
        let synthesized = tree.appendSynthesized(
            conversationID: cid, parentID: user.id,
            drafts: drafts.reversed(), providerID: "synth", modelID: "remote-synth"
        )

        XCTAssertEqual(synthesized.kind, .synthesized)
        XCTAssertEqual(synthesized.drafts.map(\.sourceLabel), ["On-device", "Remote"], "drafts keep declared order")
        XCTAssertEqual(
            tree.visiblePath(activeLeafID: synthesized.id).count, 2,
            "a synthesized turn replays as a single assistant node"
        )
        XCTAssertEqual(tree.count, 2, "two nodes total, not one per draft")
    }
}
