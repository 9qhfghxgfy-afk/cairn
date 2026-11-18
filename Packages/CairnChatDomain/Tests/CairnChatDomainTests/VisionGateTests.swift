import XCTest
@testable import CairnChatDomain

/// The vision gate: an image either reaches a model that can see it, or the turn does not go out.
///
/// This file exists because the failure it prevents is the worst one in M6 — a photo vanishing on the way
/// to a model that cannot see, and an answer describing a picture that was never delivered. Nothing here
/// is allowed to be a warning the user can miss.
final class VisionGateTests: XCTestCase {
    private func image(_ name: String) -> ChatAttachment {
        ChatAttachment.image(payload: Data([0xFF, 0xD8, 0xFF]), name: name)
    }

    private func document(_ name: String) -> ChatAttachment {
        ChatAttachment.document(payload: Data("text".utf8), name: name, text: "text")
    }

    func testATurnWithNothingAttachedHasNothingToGate() {
        XCTAssertEqual(VisionGate.decide(attachments: [], modelSees: false), .nothingAttached)
        XCTAssertFalse(VisionGate.decide(attachments: [], modelSees: false).blocksSend)
        XCTAssertNil(VisionGate.message(for: .nothingAttached))
    }

    func testADocumentAloneNeverTriggersTheGateAndNeedsNoVision() {
        // A document is read on the phone; only its passages travel. A text-only engine can still answer a
        // question about a file, so refusing that turn would be an invented limit.
        let decision = VisionGate.decide(attachments: [document("notes.md")], modelSees: false)
        XCTAssertEqual(decision, .nothingAttached)
        XCTAssertFalse(decision.blocksSend)
    }

    func testAnImageAgainstAnEngineThatCannotSeeBlocksTheSend() {
        let decision = VisionGate.decide(attachments: [image("photo.jpg")], modelSees: false)
        XCTAssertEqual(decision, .cannotSee(imageCount: 1))
        XCTAssertTrue(decision.blocksSend)
    }

    func testAnImageAgainstAnEngineThatCanSeePassesAndCountsEveryImage() {
        let staged = [image("one.jpg"), image("two.png"), document("notes.md")]
        let decision = VisionGate.decide(attachments: staged, modelSees: true)
        XCTAssertEqual(decision, .allows(imageCount: 2))
        XCTAssertFalse(decision.blocksSend)
        XCTAssertEqual(decision.imageCount, 2)
    }

    func testTheRefusalSaysHowManyImagesAndWhatToDoAboutIt() {
        let message = VisionGate.message(for: .cannotSee(imageCount: 3)) ?? ""
        XCTAssertTrue(message.contains("3 images"))
        XCTAssertTrue(message.contains("remove") || message.contains("Choose a model"))
        XCTAssertNil(VisionGate.message(for: .allows(imageCount: 3)))
    }

    func testTheStandingWarningAndTheRefusalUseOneWording() {
        let staged = [image("photo.jpg")]
        XCTAssertEqual(
            VisionGate.warning(for: staged, modelSees: false),
            VisionGate.message(for: VisionGate.decide(attachments: staged, modelSees: false))
        )
        XCTAssertNil(VisionGate.warning(for: staged, modelSees: true))
    }

    func testTheGateBlamesTheEngineNotTheUserAndNeverLosesTheFile() {
        let message = VisionGate.message(for: .cannotSee(imageCount: 1)) ?? ""
        XCTAssertTrue(message.contains("Cairn will not quietly drop"))
    }
}
