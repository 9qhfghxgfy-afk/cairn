import Foundation
import Testing
@testable import CairnInferenceLocal

struct HuggingFaceRepoIDTests {
    @Test func acceptsAnOwnerAndRepository() {
        #expect(HuggingFaceRepoID.parse("mlx-community/Qwen3-4B-MLX-4bit").repoID
            == "mlx-community/Qwen3-4B-MLX-4bit")
        #expect(HuggingFaceRepoID.parse("  org/sub.name-1  ").repoID == "org/sub.name-1")
    }

    @Test func rejectsShapesThatAreNotRepoNames() {
        #expect(HuggingFaceRepoID.parse("").repoID == nil)
        #expect(HuggingFaceRepoID.parse("gpt-only-owner") == .rejected(.missingNamespace))
        #expect(HuggingFaceRepoID.parse("https://example.invalid/a/b") == .rejected(.looksLikeURL))
        #expect(HuggingFaceRepoID.parse("org/../etc") == .rejected(.pathTraversal))
        #expect(HuggingFaceRepoID.parse("org/a b") == .rejected(.hasWhitespace))
        #expect(HuggingFaceRepoID.parse("org/a?b") == .rejected(.illegalCharacter))
        #expect(HuggingFaceRepoID.parse("org/a\\b") == .rejected(.illegalCharacter))
        #expect(HuggingFaceRepoID.parse(String(repeating: "a", count: 300)) == .rejected(.tooLong))
    }

    @Test func leadingOrTrailingSlashIsIllegal() {
        #expect(HuggingFaceRepoID.parse("/org/repo") == .rejected(.illegalCharacter))
        #expect(HuggingFaceRepoID.parse("org/repo/") == .rejected(.illegalCharacter))
    }
}

struct CatalogQueryTests {
    private var entry: OnDeviceCatalogEntry {
        OnDeviceCatalogEntry(
            repoID: "mlx-community/Tool-Model",
            displayName: "Tool Model",
            weightsBytes: 1_000_000_000,
            defaultContextLength: 4096,
            capabilities: [.tools],
            addedToLibrary: OnDeviceCatalog.day(2025, 1, 1)
        )
    }

    @Test func searchMatchesDisplayNameAndRepoID() {
        #expect(CatalogQuery.matches(entry, by: CatalogFilter(searchText: "tool")))
        #expect(CatalogQuery.matches(entry, by: CatalogFilter(searchText: "mlx-community")))
        #expect(!CatalogQuery.matches(entry, by: CatalogFilter(searchText: "vision")))
    }

    @Test func capabilityChipsNarrowRatherThanWiden() {
        #expect(CatalogQuery.matches(entry, by: CatalogFilter(requiredCapabilities: [.tools])))
        #expect(!CatalogQuery.matches(entry, by: CatalogFilter(requiredCapabilities: [.vision])))
    }

    @Test func curatedLibraryCarriesNoInventedBadges() {
        for item in OnDeviceCatalog.entries where item.capabilities.isEmpty {
            #expect(item.capabilities.isEmpty, "\(item.repoID) carries an unsupported badge claim")
        }
        #expect(OnDeviceCatalog.entries.contains { $0.repoID == "mlx-community/Qwen3-4B-MLX-4bit" })
    }

    @Test func typedRepoIDNotInLibraryBecomesInstallable() {
        let results = CatalogQuery.apply(CatalogFilter(searchText: "some-org/Custom-Model-4bit"))
        #expect(results.map(\.repoID).contains("some-org/Custom-Model-4bit"))
        #expect(results.first?.capabilities.isEmpty == true)
    }

    @Test func malformedSearchTextYieldsNothingInstallable() {
        #expect(CatalogQuery.unlistedMatch(for: "https://example.invalid/a/b").isEmpty)
        #expect(CatalogQuery.unlistedMatch(for: "just-a-name").isEmpty)
    }

    @Test func sortsAreStableAndDistinct() throws {
        let byNewest = CatalogQuery.sorted(.newest, OnDeviceCatalog.entries)
        let bySmallest = CatalogQuery.sorted(.smallest, OnDeviceCatalog.entries)
        let newestFirst = try #require(byNewest.first?.addedToLibrary)
        let newestLast = try #require(byNewest.last?.addedToLibrary)
        #expect(newestFirst >= newestLast)
        let smallestFirst = try #require(bySmallest.first?.weightsBytes)
        let smallestLast = try #require(bySmallest.last?.weightsBytes)
        #expect(smallestFirst <= smallestLast)
    }
}

struct ModelConfigReaderTests {
    @Test func publishedKeysAreReadAndNothingIsInvented() {
        let facts = ModelConfigReader.read(from: [
            "num_hidden_layers": 32,
            "num_key_value_heads": 8,
            "head_dim": 128,
            "max_position_embeddings": 40_960,
        ])
        #expect(facts.layerCount == 32)
        #expect(facts.kvHeadCount == 8)
        #expect(facts.headDimension == 128)
        #expect(facts.contextLength == 40_960)
        #expect(facts.capabilities.isEmpty)
    }

    @Test func headDimIsDerivedOnlyFromPublishedOperands() {
        let facts = ModelConfigReader.read(from: ["hidden_size": 4096, "num_attention_heads": 32])
        #expect(facts.headDimension == 128)
        #expect(ModelConfigReader.read(from: ["hidden_size": 4096]).headDimension == nil)
    }

    @Test func capabilityBadgesComeFromStatedFlagsOnly() {
        let facts = ModelConfigReader.read(from: [
            "supports_vision": true, "supports_tools": "false", "supports_thinking": 1,
        ])
        #expect(facts.capabilities == [.vision])
    }

    @Test func unreadableConfigYieldsEmptyFacts() {
        #expect(ModelConfigReader.read(Data("<html>".utf8)).layerCount == nil)
    }
}
