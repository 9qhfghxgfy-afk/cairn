import XCTest
@testable import CairnChatDomain

final class ChatTreeQueryTests: XCTestCase {

    let cid = UUID()

    /// user -> assistant(v1) + assistant(v2) -> user(follow up)
    private func fixture() -> (a1: ChatNode, a2: ChatNode, nodes: [ChatNode]) {
        var nodes: [ChatNode] = []
        let user = ChatTree.append(to: nodes, conversationID: cid, parentID: nil, role: .user, text: "ask").node
        nodes = ChatTree.append(to: nodes, conversationID: cid, parentID: user.id, role: .assistant, text: "v1").nodes
        let a1 = nodes.last!
        let a2 = ChatTree.append(to: nodes, conversationID: cid, parentID: user.id, role: .assistant, text: "v2").node
        nodes = ChatTree.append(to: nodes, conversationID: cid, parentID: a2.id, role: .user, text: "next").node
        return (a1, a2, nodes)
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
        let empty: [ChatNode] = []
        let userA = ChatTree.append(to: empty, conversationID: cid, parentID: nil, role: .user, text: "first").node
        let withAnswer = ChatTree.append(to: empty + [userA], conversationID: cid, parentID: userA.id, role: .assistant, text: "answer")
        let answer = withAnswer.node
        let userB = ChatTree.append(to: withAnswer.nodes, conversationID: cid, parentID: answer.id, role: .user, text: "next").node

        var params = SamplingParams.default
        params.systemPrompt = "You are Cairn."

        let path = ChatTree.visiblePath(nodes: withAnswer.nodes + [userB], activeLeafID: userB.id)
        let payload = ChatTree.messages(for: path, params: params)
        XCTAssertEqual(payload.map(\.role), [.system, .user, .assistant, .user])
        XCTAssertEqual(payload.first?.text, "You are Cairn.")

        let streaming = ChatNode(conversationID: cid, parentID: userB.id, role: .assistant, text: "", state: .streaming)
        let withEmpty = ChatTree.messages(
            for: ChatTree.visiblePath(nodes: withAnswer.nodes + [userB, streaming], activeLeafID: streaming.id),
            params: params
        )
        XCTAssertEqual(withEmpty.count, 4, "an empty streaming node must not be sent to the backend")
    }

    func testSynthesizedTurnIsOneNodeCarryingItsDrafts() {
        let empty: [ChatNode] = []
        let user = ChatTree.append(to: empty, conversationID: cid, parentID: nil, role: .user, text: "compare").node
        let drafts = [
            CandidateDraft(order: 0, sourceLabel: "On-device", providerID: "device", modelID: "apple-fm"),
            CandidateDraft(order: 1, sourceLabel: "Remote", providerID: "ollama", modelID: "qwen3:8b"),
        ]
        let result = ChatTree.synthesizedNode(
            nodes: [user], conversationID: cid, parentID: user.id,
            drafts: drafts.reversed(), providerID: "synth", modelID: "remote-synth"
        )

        XCTAssertEqual(result.node.kind, .synthesized)
        XCTAssertEqual(result.node.drafts.map(\.sourceLabel), ["On-device", "Remote"], "drafts keep declared order")
        XCTAssertEqual(
            ChatTree.visiblePath(nodes: result.nodes, activeLeafID: result.node.id).count, 2,
            "a synthesized turn replays as a single assistant node"
        )
    }
}
