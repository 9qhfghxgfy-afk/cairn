import Foundation
import Testing
@testable import CairnInferenceLocal

private func scratchDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cairn-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

struct SHA256DigestTests {
    @Test func knownVector() {
        #expect(SHA256Digest.hex(of: Data("abc".utf8))
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func streamsAFileInChunksWithoutLoadingItWhole() throws {
        let root = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("payload.bin")
        var payload = Data()
        for byte: UInt8 in 0..<255 { payload.append(Data(repeating: byte, count: 4096)) }
        try payload.write(to: file)

        #expect(SHA256Digest.hex(of: payload) == SHA256Digest.hex(ofFileAt: file, chunkBytes: 100_000))
    }

    @Test func missingFileIsNotAMatch() {
        let missing = scratchDirectory().appendingPathComponent("nope.bin")
        #expect(SHA256Digest.hex(ofFileAt: missing) == nil)
        #expect(!SHA256Digest.matches(expected: "abc", fileAt: missing))
    }

    @Test func matchIgnoresHexCaseAndTrimsWhitespace() throws {
        let root = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("a.bin")
        try Data("abc".utf8).write(to: file)
        let upper = SHA256Digest.hex(of: Data("abc".utf8)).uppercased()
        #expect(SHA256Digest.matches(expected: " \(upper) ", fileAt: file))
        #expect(!SHA256Digest.matches(expected: String(repeating: "0", count: 64), fileAt: file))
    }
}

struct ModelStoreLayoutTests {
    @Test func slugIsFilesystemSafe() {
        #expect(ModelStoreLayout.slug(for: "mlx-community/Qwen3-4B-MLX-4bit")
            == "mlx-community-Qwen3-4B-MLX-4bit")
        #expect(ModelStoreLayout.slug(for: "org/../../etc").contains("..") == false)
        #expect(ModelStoreLayout.slug(for: "///") == "model")
    }

    @Test func sizeOnDiskCountsRealBytes() throws {
        let root = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = ModelStoreLayout(rootURL: root)
        let directory = layout.directory(for: "org/model")
        try layout.install("org/model")
        try Data(repeating: 7, count: 4096).write(to: directory.appendingPathComponent("weights.bin"))
        #expect(layout.sizeOnDisk(at: directory) == 4096)

        try layout.remove("org/model")
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func manifestSurvivesARoundTrip() throws {
        let manifest = InstalledModelManifest(
            repoID: "org/model",
            installedAt: Date(timeIntervalSince1970: 1_700_000_000),
            files: [InstalledModelFile(name: "config.json", bytes: 12, sha256: "ab"),
                    InstalledModelFile(name: "model.safetensors", bytes: 99, sha256: nil)]
        )
        let data = try #require(manifest.encoded())
        let restored = try #require(InstalledModelManifest.decode(data))
        #expect(restored == manifest)
        #expect(restored.totalBytes == 111)
        #expect(restored.verifiableFiles.map(\.name) == ["config.json"])
    }
}

struct ModelFilePlanTests {
    @Test func onlyFilesNeededToRunTheModelArePulled() {
        let listing: [ModelFileListing] = [
            .init(name: "config.json"),
            .init(name: "model.safetensors"),
            .init(name: "tokenizer.json"),
            .init(name: "special_tokens_map.json"),
            .init(name: "model.gguf"),
            .init(name: ".gitattributes"),
            .init(name: "README.md"),
            .init(name: "notes/colab.ipynb"),
        ]
        let names = ModelFilePlan.select(from: listing, repoID: "org/model").map(\.name)
        #expect(names == ["config.json", "model.safetensors", "tokenizer.json", "special_tokens_map.json"])
    }

    @Test func unsafeFileNamesAreNotJoinedOntoTheStorePath() {
        let listing = [ModelFileListing(name: "../../escape.bin")]
        #expect(ModelFilePlan.select(from: listing, repoID: "org/model").isEmpty)
        #expect(!HuggingFaceEndpoints.isSafeFileName("/absolute.bin"))
        #expect(!HuggingFaceEndpoints.isSafeFileName("a/../b"))
    }

    @Test func totalBytesIsNilWhenAnyFileWentUnlisted() {
        let plan = ModelFilePlan.select(
            from: [.init(name: "config.json", bytes: 10), .init(name: "model.safetensors")],
            repoID: "org/model"
        )
        #expect(ModelFilePlan.totalBytes(of: plan) == nil)
        let complete = ModelFilePlan.select(
            from: [.init(name: "config.json", bytes: 10), .init(name: "model.safetensors", bytes: 20)],
            repoID: "org/model"
        )
        #expect(ModelFilePlan.totalBytes(of: complete) == 30)
    }

    @Test func listingDecoderToleratesBothPublishedShapes() {
        let modern = Data(#"[{"path":"config.json","size":12,"lsha":"ab"}]"#.utf8)
        let legacy = Data(#"[{"filename":"model.safetensors","size":99,"sha256":"cd"}]"#.utf8)
        // The shape Cairn actually calls: a model record whose files sit under `siblings`, with the
        // content digest of a large file published under `lfs.sha256` rather than as the git oid.
        let record = Data(#"{"_id":"models/x","siblings":[{"rfilename":"config.json","size":11},{"rfilename":"model.safetensors","size":695,"lfs":{"sha256":"35e3","size":695}}]}"#.utf8)
        // A git object id is a hash of the pointer file, never of the bytes, so it is not read as a digest.
        let tree = Data(#"[{"type":"file","oid":"52373f","size":1570,"path":"config.json"}]"#.utf8)
        #expect(ModelFilePlan.listing(from: modern) == [ModelFileListing(name: "config.json", bytes: 12, sha256: "ab")])
        #expect(ModelFilePlan.listing(from: legacy) == [ModelFileListing(name: "model.safetensors", bytes: 99, sha256: "cd")])
        #expect(ModelFilePlan.listing(from: record) == [
            ModelFileListing(name: "config.json", bytes: 11),
            ModelFileListing(name: "model.safetensors", bytes: 695, sha256: "35e3"),
        ])
        #expect(ModelFilePlan.listing(from: tree) == [ModelFileListing(name: "config.json", bytes: 1570)])
        #expect(ModelFilePlan.listing(from: Data("<html>".utf8)).isEmpty)
    }
}
