import Foundation
import XCTest
@testable import CairnChatDomain

/// The Installed tab is one list assembled from three sources, and the two ways that can go wrong are the
/// two things pinned here: a source going missing, and two same-named models collapsing into one row.
final class InstalledInventoryTests: XCTestCase {

    private func phoneRow(
        _ repoID: String,
        size: Int64 = 1_200_000_000,
        format: ModelFormat = .mlx
    ) -> InstalledLocalModel {
        InstalledLocalModel(
            repoID: repoID,
            displayName: repoID.components(separatedBy: "/").last ?? repoID,
            sizeBytes: size,
            fileCount: 3,
            installedOn: Date(timeIntervalSince1970: 1_700_000_000),
            format: format
        )
    }

    func testAPhonesFoldersBecomeRowsOwnedByThisPhone() {
        let rows = InstalledInventory.entries(for: [phoneRow("mlx-community/Qwen3-4B-4bit")])
        XCTAssertEqual(rows.count, 1)
        let row = rows[0]
        XCTAssertEqual(row.id, "phone:mlx-community/Qwen3-4B-4bit")
        XCTAssertEqual(row.host, .thisPhone)
        XCTAssertEqual(row.hostModelID, "mlx-community/Qwen3-4B-4bit")
        XCTAssertEqual(row.badgeText, "MLX")
        XCTAssertEqual(row.sourceLine, "On this iPhone")
        XCTAssertTrue(row.canDelete)
        XCTAssertNil(row.sourceName, "this iPhone needs no further naming")
    }

    func testAFolderNobodyMeasuredSaysSoRatherThanBorrowingASize() {
        let row = InstalledInventory.entries(for: [phoneRow("a", size: 0)])[0]
        XCTAssertNil(row.sizeBytes)
        XCTAssertTrue(row.canDelete, "an unreadable folder is still this phone's to remove")
    }

    func testTheSystemModelIsListedOnlyWhenThisPhoneCanRunIt() {
        XCTAssertNil(InstalledInventory.appleIntelligence(available: false, reason: "Turn on Apple Intelligence in Settings"))
        let row = InstalledInventory.appleIntelligence(available: true, reason: "Available on this device")
        XCTAssertNotNil(row)
        XCTAssertEqual(row?.id, InstalledModelEntry.systemID)
        XCTAssertEqual(row?.format, .appleIntelligence)
        XCTAssertEqual(row?.detail, "Available on this device")
        XCTAssertFalse(row?.canDelete ?? true, "iOS evicts this model, so Cairn draws no button")
    }

    func testAServerRowSpeaksOnlyInThatServersWords() {
        let rows = InstalledInventory.entries(
            for: [ModelInfo(id: "qwen3:4b", displayName: "qwen3:4b", providerID: "ollama",
                            parameterSize: "4.0B")],
            profileID: "prof-1",
            serverName: "Studio Mac"
        )
        let row = rows[0]
        XCTAssertEqual(row.id, "server:prof-1:qwen3:4b")
        XCTAssertEqual(row.host, .remoteServer)
        XCTAssertEqual(row.hostModelID, "qwen3:4b")
        XCTAssertEqual(row.sourceName, "Studio Mac")
        XCTAssertEqual(row.detail, "4.0B")
        XCTAssertFalse(row.canDelete)
    }

    func testOneNameOnTwoHostsSurvivesTheMergeAsTwoRows() {
        let phone = InstalledInventory.entries(for: [phoneRow("qwen3:4b", format: .gguf)])
        let server = InstalledInventory.entries(
            for: [ModelInfo(id: "qwen3:4b", displayName: "qwen3:4b", providerID: "ollama")],
            profileID: "prof-1",
            serverName: "Studio Mac"
        )
        let merged = InstalledInventory.merge([phone, server])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.map(\.badgeText), ["GGUF", "Server"])
    }

    func testTheMergeKeepsThisPhonesRowsAheadOfAServersReport() {
        let phone = InstalledInventory.entries(for: [phoneRow("a"), phoneRow("b")])
        let system = InstalledInventory.appleIntelligence(available: true, reason: "Available")
        let server = InstalledInventory.entries(
            for: [ModelInfo(id: "x", displayName: "x", providerID: "ollama")],
            profileID: "p", serverName: "Box"
        )
        let merged = InstalledInventory.merge([phone, [system].compactMap { $0 }, server])
        XCTAssertEqual(merged.map(\.host), [.thisPhone, .thisPhone, .system, .remoteServer])
    }

    func testTheMergeDropsOnlyTheSameRowReportedTwice() {
        let once = InstalledInventory.entries(for: [phoneRow("a")])
        let merged = InstalledInventory.merge([once, once, once])
        XCTAssertEqual(merged.count, 1)
    }

    func testAServerThatRefusesLeavesThisPhonesRowsAlone() {
        // The merge has no notion of failure by design — a group that failed arrives empty — so the honest
        // shape of "the server is down" is this: the phone's rows, nothing else.
        let phone = InstalledInventory.entries(for: [phoneRow("a")])
        let merged = InstalledInventory.merge([phone, []])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.host, .thisPhone)
    }

    func testFormatComesFromTheFilesRatherThanTheName() {
        XCTAssertEqual(ModelFormat.detect(fileNames: ["model.gguf"]), .gguf)
        XCTAssertEqual(ModelFormat.detect(fileNames: ["MODEL.GGUF"]), .gguf)
        XCTAssertEqual(ModelFormat.detect(fileNames: ["model-00001.safetensors"]), .mlx)
        // Both shapes in one repository: the GGUF file is what a GGUF download asked for.
        XCTAssertEqual(ModelFormat.detect(fileNames: ["a.safetensors", "b.gguf"]), .gguf)
        XCTAssertNil(ModelFormat.detect(fileNames: ["README.md", "config.json"]))
        XCTAssertNil(ModelFormat.detect(fileNames: []))
    }
}
