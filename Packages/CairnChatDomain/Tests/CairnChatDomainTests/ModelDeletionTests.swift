import Foundation
import XCTest
@testable import CairnChatDomain

/// Deleting a model is the one thing on this screen that cannot be undone, so the rule that decides it is
/// tested rather than eyeballed: which rows may offer a Delete, what the confirmation is allowed to
/// promise, and what each refusal tells the person.
final class ModelDeletionTests: XCTestCase {

    private func phoneEntry(size: Int64? = 1_500_000_000) -> InstalledModelEntry {
        InstalledModelEntry(
            id: "phone:a/b", displayName: "B", format: .mlx, host: .thisPhone,
            hostModelID: "a/b", sizeBytes: size
        )
    }

    private var systemEntry: InstalledModelEntry {
        InstalledModelEntry(
            id: InstalledModelEntry.systemID, displayName: "Apple Intelligence",
            format: .appleIntelligence, host: .system
        )
    }

    private var serverEntry: InstalledModelEntry {
        InstalledModelEntry(
            id: "server:p:qwen3:4b", displayName: "qwen3:4b", format: .server, host: .remoteServer,
            hostModelID: "qwen3:4b", sourceName: "Studio Mac"
        )
    }

    func testThisPhonesFolderIsDeletableAndSaysWhatItFrees() {
        let verdict = ModelDeletion.verdict(for: phoneEntry())
        XCTAssertEqual(verdict, .allowed(freedBytes: 1_500_000_000))
        XCTAssertNil(verdict.blockReason)
    }

    func testAnUnmeasuredFolderIsStillDeletableAndPromisesNoFigure() {
        let entry = phoneEntry(size: nil)
        let verdict = ModelDeletion.verdict(for: entry)
        XCTAssertEqual(verdict, .allowed(freedBytes: nil))
        let body = ModelDeletion.confirmationBody(for: entry, freedText: nil)
        XCTAssertFalse(body.contains("GB"))
        XCTAssertTrue(body.contains("not been measured"))
    }

    func testTheBuiltInModelAndAServersModelAreBothRefusedInTheirOwnWords() {
        let system = ModelDeletion.verdict(for: systemEntry)
        XCTAssertEqual(system, .blocked(.systemManaged))
        XCTAssertTrue(system.blockReason?.contains("iOS manages") ?? false)

        let server = ModelDeletion.verdict(for: serverEntry)
        XCTAssertEqual(server, .blocked(.notOnThisPhone))
        XCTAssertTrue(server.blockReason?.contains("server") ?? false)
    }

    func testNoEntryBuiltForAnotherHostCanClaimToDelete() {
        XCTAssertFalse(systemEntry.canDelete)
        XCTAssertFalse(serverEntry.canDelete)
        XCTAssertTrue(phoneEntry().canDelete)
    }

    func testAConflictIsStatedAsAReasonThePersonCanActOn() {
        XCTAssertTrue(ModelDeletionBlock.turnRunning.reasonText.contains("still being written"))
        XCTAssertTrue(ModelDeletionBlock.systemManaged.reasonText.contains("cannot delete"))
        XCTAssertTrue(ModelDeletionBlock.storageUnavailable.reasonText.contains("model storage"))
    }

    func testAFailedRemovalReportsTheSameReasonsAsTheRuleWould() {
        XCTAssertEqual(InstalledModelError.turnRunning.block, .turnRunning)
        XCTAssertEqual(InstalledModelError.systemManaged.block, .systemManaged)
        XCTAssertEqual(
            InstalledModelError.systemManaged.errorDescription,
            ModelDeletionBlock.systemManaged.reasonText
        )
        XCTAssertNotNil(InstalledModelError.removalFailed.errorDescription)
    }

    func testTheConfirmationNamesTheModelRatherThanTheRow() {
        XCTAssertEqual(
            ModelDeletion.confirmationTitle(for: serverEntry),
            "Delete qwen3:4b?"
        )
    }

    func testTheInfoExplainsTheHostThatOwnsTheBytes() {
        XCTAssertTrue(phoneEntry().infoText.contains("this iPhone"))
        XCTAssertTrue(serverEntry.infoText.contains("Studio Mac"))
        XCTAssertTrue(systemEntry.infoTitle.contains("iOS"))
        // Apple's own status sentence is carried into the popover rather than dropped.
        let ready = InstalledModelEntry(
            id: InstalledModelEntry.systemID, displayName: "Apple Intelligence",
            format: .appleIntelligence, host: .system, detail: "Available on this device"
        )
        XCTAssertTrue(ready.infoText.contains("Available on this device"))
    }
}
