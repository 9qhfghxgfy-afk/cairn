import XCTest
@testable import CairnChatDomain

/// The synthesizer's payload is deliberately the narrowest thing that can do the job: one question
/// and the drafts. Choosing a second provider for a turn must not quietly hand that provider a
/// transcript it was never asked to hold.
final class HybridSynthesisPromptTests: XCTestCase {

    private let drafts = [
        CandidateDraft(order: 0, sourceLabel: "LAN server", providerID: "lan", modelID: "server-a", text: "left says yes", state: .complete),
        CandidateDraft(order: 1, sourceLabel: "Cloud server", providerID: "cloud", modelID: "cloud-a", text: "right says no", state: .complete),
    ]

    func testThePayloadIsTheInstructionPlusTheQuestionAndTheDrafts() {
        let request = HybridSynthesisPrompt.request(
            question: "Is this a cairn?",
            drafts: drafts,
            persona: "Answer in one short paragraph.",
            synthesizer: HybridCandidate(engineID: "lan", modelID: "server-a"),
            config: ChatConfig()
        )

        XCTAssertEqual(request.messages.count, 2)
        XCTAssertEqual(request.modelID, "server-a")
        XCTAssertTrue(request.messages[0].text.hasPrefix("Answer in one short paragraph."), "the chat's persona is kept for the engine that already gets it")
        XCTAssertTrue(request.messages[0].text.contains("do not describe reasoning it did not show"))
        XCTAssertTrue(request.messages[1].text.contains("Is this a cairn?"))
        XCTAssertTrue(request.messages[1].text.contains("LAN server · server-a"))
        XCTAssertTrue(request.messages[1].text.contains("left says yes"))
        XCTAssertTrue(request.messages[1].text.contains("right says no"))
    }

    func testAPersonaFreeChatSendsTheInstructionAlone() {
        let text = HybridSynthesisPrompt.systemText(persona: "   ")
        XCTAssertEqual(text, HybridSynthesisPrompt.instruction)
    }

    func testAFailedDraftIsNamedAsFailedRatherThanSkipped() {
        let broken = CandidateDraft(
            order: 0,
            sourceLabel: "LAN server",
            providerID: "lan",
            modelID: "server-a",
            text: "partial",
            state: .failed,
            failure: "The server closed the socket."
        )
        let block = HybridSynthesisPrompt.draftsBlock([drafts[1], broken])

        // Declared order, not arrival order: candidate 1 is the primary side.
        XCTAssertTrue(block.starts(with: "Candidate 1 — LAN server"))
        XCTAssertTrue(block.contains("The server closed the socket."))

        let silent = CandidateDraft(order: 1, sourceLabel: "Cloud server", providerID: "cloud", modelID: "cloud-a", state: .cancelled)
        XCTAssertTrue(HybridSynthesisPrompt.draftsBlock([silent]).contains("no answer"))
    }
}