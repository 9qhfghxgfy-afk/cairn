import XCTest
@testable import CairnChatDomain

/// The card for a name Cairn's library does not carry.
///
/// The curated list is short; the repositories and the Ollama library are not. A screen that answers
/// "nothing here" to `some-org/some-model-GGUF` reads as a broken search, and a screen that offers a
/// bare word to a phone produces a request that fails for a reason the person cannot see. Both are
/// proved here rather than discovered on a device.
final class ModelCatalogCustomRowTests: XCTestCase {
    private var curated: [LocalCatalogRow] {
        [
            LocalCatalogRow(
                repoID: "mlx-community/Qwen3.5-2B-6bit", displayName: "Qwen 3.5 2B",
                downloadBytes: 2_219_390_841, addedOn: Date(timeIntervalSince1970: 10),
                provider: "Qwen", series: "Qwen 3.5", sortOrder: 0
            ),
            LocalCatalogRow(
                repoID: "qwen3:4b", displayName: "Qwen3 4B", downloadBytes: 2_500_000_000,
                addedOn: Date(timeIntervalSince1970: 10), provider: "Qwen", series: "Qwen3",
                sortOrder: 0, origin: .ollamaLibrary
            )
        ]
    }

    func testATypedRepositoryBecomesACardForThePhone() {
        let row = ModelCatalogQuery.customRow(
            search: " some-org/some-model-GGUF ",
            in: [curated[0]],
            origin: .onDevice
        )
        XCTAssertEqual(row?.repoID, "some-org/some-model-GGUF")
        XCTAssertEqual(row?.displayName, "some-org/some-model-GGUF")
        XCTAssertEqual(row?.origin, .custom)
        XCTAssertTrue(row?.summary.contains("Hugging Face") ?? false)
        XCTAssertNil(row?.downloadBytes, "nobody published a size, so the card states none")
    }

    /// A bare word is a valid tag and an invalid repository. The phone must not be offered a request
    /// it cannot make, and the server must be offered the tag the person meant.
    func testAPhoneNeedsARepositoryAndAServerNeedsATag() {
        XCTAssertNil(ModelCatalogQuery.customRow(search: "my-model", in: curated, origin: .onDevice))
        XCTAssertEqual(
            ModelCatalogQuery.customRow(search: "my-model:latest", in: [curated[1]], origin: .ollamaLibrary)?
                .repoID,
            "my-model:latest"
        )
        XCTAssertNil(
            ModelCatalogQuery.customRow(search: "some-org/repo", in: [curated[1]], origin: .ollamaLibrary)
        )
    }

    func testANameAlreadyInTheLibraryIsNeverOfferedTwice() {
        XCTAssertNil(
            ModelCatalogQuery.customRow(
                search: "mlx-community/Qwen3.5-2B-6bit", in: curated, origin: .onDevice
            )
        )
        XCTAssertNil(
            ModelCatalogQuery.customRow(
                search: "MLX-Community/qwen3.5-2b-6bit", in: curated, origin: .onDevice
            )
        )
    }

    func testNothingShapedLikeANameIsNotOfferedAsAModel() {
        for text in ["", "   ", "two words", "a/b/c", "org/", "/repo", "a b/c", "not/a/tag/here"] {
            XCTAssertNil(
                ModelCatalogQuery.customRow(search: text, in: curated, origin: .onDevice), text
            )
        }
        let long = String(repeating: "a", count: 121)
        XCTAssertNil(
            ModelCatalogQuery.customRow(search: "\(long)/repo", in: curated, origin: .onDevice)
        )
    }

    func testTheCustomCardIsAppendedOnlyWhenNothingMatches() {
        let rows = ModelCatalogQuery.rows(curated, filter: ModelCatalogFilter(search: "zz/qq"),
                                          origin: .onDevice)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.origin, .custom)

        // A curated model hidden by a chip is still curated, so it is not offered a second card.
        let hidden = ModelCatalogQuery.rows(
            curated,
            filter: ModelCatalogFilter(search: "Qwen 3.5", capabilities: [.vision]),
            origin: .onDevice
        )
        XCTAssertTrue(hidden.isEmpty)
    }

    func testTheCustomCardNamesTheDestinationItWasOfferedUnder() {
        let server = ModelCatalogQuery.customRow(search: "codellama:13b", in: [curated[1]],
                                                origin: .ollamaLibrary)
        XCTAssertTrue(server?.summary.contains("server") ?? false)
        XCTAssertEqual(ModelCatalogOrigin.custom.destinationText, "Install by exact name")
        XCTAssertTrue(ModelCatalogOrigin.onDevice.destinationText.contains("phone"))
        XCTAssertTrue(ModelCatalogOrigin.ollamaLibrary.destinationText.contains("server"))
    }
}
