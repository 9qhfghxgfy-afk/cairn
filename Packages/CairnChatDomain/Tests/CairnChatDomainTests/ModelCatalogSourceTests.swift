import Foundation
import XCTest
@testable import CairnChatDomain

/// The Download tab opens pre-populated on a named source, whichever server opened it.
///
/// The two facts worth pinning are the two the user sees: which source the tab opens on, and that a
/// source is never an empty list. Everything else on that screen is derived from those.
final class ModelCatalogSourceTests: XCTestCase {

    func testTheSourceSwitcherNamesTheTwoLibraries() {
        XCTAssertEqual(ModelCatalogOrigin.onDevice.sourceLabel, "Hugging Face")
        XCTAssertEqual(ModelCatalogOrigin.ollamaLibrary.sourceLabel, "Ollama")
        XCTAssertFalse(ModelCatalogOrigin.onDevice.sourceBlurb.isEmpty)
        XCTAssertFalse(ModelCatalogOrigin.ollamaLibrary.sourceBlurb.isEmpty)
    }

    func testTheOpeningSourceComesFromTheServerThatOpenedModels() {
        // On-Device opened it — no server profile at all — so this phone's own MLX weights lead.
        XCTAssertEqual(ModelCatalogOpening.origin(forKind: nil), .onDevice)
        // Any remote server opens on the Ollama library, including one that cannot pull: a readable tag
        // list beats an empty tab, and the sheet says which server can take the tag.
        for kind in ServerProfileKind.allCases {
            XCTAssertEqual(ModelCatalogOpening.origin(forKind: kind), .ollamaLibrary, kind.rawValue)
        }
    }

    func testOnlyAnOllamaServerIsAskedToPull() {
        XCTAssertTrue(ModelCatalogOpening.pullsDirectly(fromKind: .ollama))
        XCTAssertTrue(ModelCatalogOpening.pullsDirectly(fromKind: .ollamaCloud))
        XCTAssertFalse(ModelCatalogOpening.pullsDirectly(fromKind: .lmStudio))
        XCTAssertFalse(ModelCatalogOpening.pullsDirectly(fromKind: .openAICompatible))
        XCTAssertFalse(ModelCatalogOpening.pullsDirectly(fromKind: nil))
    }

    func testBothSourcesArePopulatedWithNothingTyped() {
        let phone = ModelCatalog.rows(for: .onDevice)
        let server = ModelCatalog.rows(for: .ollamaLibrary)
        XCTAssertFalse(phone.isEmpty, "Hugging Face must never open empty")
        XCTAssertFalse(server.isEmpty, "Ollama must never open empty")
        XCTAssertTrue(phone.allSatisfy { $0.origin == .onDevice })
        XCTAssertTrue(server.allSatisfy { $0.origin == .ollamaLibrary })
    }

    func testTheNamedMLXBuildsAreOnThePhoneList() {
        let held = Set(ModelCatalog.onDevice.map(\.repoID))
        for id in [
            "mlx-community/Qwen3.5-2B-4bit", "mlx-community/Qwen3.5-4B-4bit",
            "mlx-community/gemma-3-4b-it-4bit", "mlx-community/Llama-3.2-3B-Instruct-4bit",
            "mlx-community/Qwen2.5-Coder-3B-Instruct-4bit",
            "mlx-community/DeepSeek-R1-Distill-Qwen-1.5B-4bit",
        ] {
            XCTAssertTrue(held.contains(id), "\(id) missing from the Hugging Face library")
        }
    }

    func testTheNamedOllamaTagsAreOnTheServerList() {
        let held = Set(ModelCatalog.ollama.map(\.repoID))
        for tag in [
            "qwen3:4b", "qwen3:8b", "gemma3:4b", "llama3.2:3b",
            "qwen2.5-coder:7b", "deepseek-r1:8b", "llava:7b",
        ] {
            XCTAssertTrue(held.contains(tag), "\(tag) missing from the Ollama library")
        }
    }

    func testEveryCuratedRowStatesASizeAndNobodyIsMarkedInstalledAtRest() {
        // A card with no size is a card that cannot warn about storage, so the curated rows state one;
        // and a list that opens claiming a model is installed would be a claim nothing checked.
        for row in ModelCatalog.onDevice + ModelCatalog.ollama {
            XCTAssertGreaterThan(row.downloadBytes ?? 0, 0, "\(row.repoID) states no size")
            XCTAssertFalse(row.isInstalled, "\(row.repoID) opens marked installed")
            XCTAssertTrue(row.origin == .onDevice || row.origin == .ollamaLibrary)
        }
    }

    func testThePhoneListIsRankedWithoutGapsInTheOrder() {
        let orders = ModelCatalog.onDevice.map(\.sortOrder)
        XCTAssertEqual(orders, orders.sorted(), "the Popular order must be the list's own order")
        XCTAssertEqual(Set(orders).count, orders.count, "two rows may not share a rank")
    }
}
