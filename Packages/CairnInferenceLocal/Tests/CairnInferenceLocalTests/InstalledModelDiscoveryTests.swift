import Foundation
import Testing

@testable import CairnInferenceLocal

/// What counts as installed, proven against real folders rather than against a double.
///
/// The bug this holds shut is a phone with three downloaded models being told it had none, which came
/// about because three readers of the same folder disagreed — one wanted a manifest, one wanted a manifest
/// plus `config.json` plus weights, and one asked for nothing at all. So these tests are about the three
/// questions separately: what is installed, what MLX can load, and what a half-finished download is.
struct InstalledModelDiscoveryTests {

    private func store() -> (layout: ModelStoreLayout, fm: FileManager) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("cairn-discovery-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        return (ModelStoreLayout(rootURL: root), fm)
    }

    /// Writes a finished model folder: the files, then the manifest, which is the order the installer
    /// uses and the reason a manifest is the marker of a completed download.
    private func install(
        _ repoID: String,
        layout: ModelStoreLayout,
        fm: FileManager,
        fileNames: [String],
        installedAt: Date
    ) {
        let directory = layout.directory(for: repoID)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in fileNames {
            let url = directory.appendingPathComponent(name)
            try? Data(repeating: 7, count: 8).write(to: url)
        }
        let manifest = InstalledModelManifest(
            repoID: repoID,
            installedAt: installedAt,
            files: fileNames.map { InstalledModelFile(name: $0, bytes: 8, sha256: nil) }
        )
        if let data = manifest.encoded() {
            try? data.write(
                to: directory.appendingPathComponent(InstalledModelManifest.manifestFileName)
            )
        }
    }

    private let old = Date(timeIntervalSince1970: 1_700_000_000)
    private let recent = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func everyInstalledFolderIsListedWhateverRuntimeItsFilesDescribe() throws {
        let held = store()
        install(
            "mlx-community/A-4bit", layout: held.layout, fm: held.fm,
            fileNames: ["config.json", "model.safetensors"],
            installedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        install(
            "mlx-community/B-6bit", layout: held.layout, fm: held.fm,
            fileNames: ["config.json", "model-00001.safetensors"],
            installedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        install(
            "gguf-org/C-Q4", layout: held.layout, fm: held.fm,
            fileNames: ["C.Q4_K_M.gguf"],
            installedAt: Date(timeIntervalSince1970: 1_600_000_000)
        )

        let found = InstalledModelDiscovery.readings(layout: held.layout, fileManager: held.fm)
        #expect(found.map { $0.repoID }
                == ["mlx-community/B-6bit", "mlx-community/A-4bit", "gguf-org/C-Q4"],
                "newest first, and a GGUF folder is installed whatever this build links")
        #expect(found.filter { $0.isMLXLoadable }.map { $0.repoID }
                == ["mlx-community/B-6bit", "mlx-community/A-4bit"])
        #expect(found.first?.fileCount == 2)
        #expect(found.allSatisfy { $0.manifestBytes > 0 })
    }

    @Test func aHalfFinishedDownloadIsNotInstalled() throws {
        let held = store()
        // The weights arrived; the manifest, written last, did not.
        let partial = held.layout.directory(for: "mlx-community/Partial")
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 8).write(to: partial.appendingPathComponent("config.json"))
        try Data(repeating: 1, count: 8).write(to: partial.appendingPathComponent("model.safetensors"))

        let found = InstalledModelDiscovery.readings(layout: held.layout, fileManager: held.fm)
        #expect(found.isEmpty, "bytes arriving is not a model installed")
        #expect(InstalledModelDiscovery.mlxLoadable(layout: held.layout, fileManager: held.fm).isEmpty)
    }

    /// A folder can be installed and still not be loadable by MLX — a GGUF download has no
    /// `config.json`, and a weights folder whose config never arrived cannot be handed to the runtime.
    /// Both stay in the installed list; neither may be offered as a model to load.
    @Test func installedAndLoadableAreAnsweredSeparately() throws {
        let held = store()
        install(
            "gguf-org/WeightsOnly", layout: held.layout, fm: held.fm,
            fileNames: ["model.Q4_K_M.gguf"], installedAt: old
        )
        install(
            "mlx-community/NoConfig", layout: held.layout, fm: held.fm,
            fileNames: ["model.safetensors"], installedAt: recent
        )

        let found = InstalledModelDiscovery.readings(layout: held.layout, fileManager: held.fm)
        #expect(found.count == 2, "both are installed")
        #expect(found.allSatisfy { !$0.isMLXLoadable })
        #expect(InstalledModelDiscovery.mlxLoadable(layout: held.layout, fileManager: held.fm).isEmpty)
    }

    /// Deleting a model is the other half of the count. The Servers row reads this on every reload, so a
    /// folder that went away has to stop being counted the moment the screen is redrawn.
    @Test func removalIsReflectedInTheNextReading() throws {
        let held = store()
        install(
            "mlx-community/Kept", layout: held.layout, fm: held.fm,
            fileNames: ["config.json", "model.safetensors"], installedAt: old
        )
        install(
            "mlx-community/Dropped", layout: held.layout, fm: held.fm,
            fileNames: ["config.json", "model.safetensors"], installedAt: recent
        )
        #expect(InstalledModelDiscovery.readings(layout: held.layout, fileManager: held.fm).count == 2)

        try held.layout.remove("mlx-community/Dropped", fileManager: held.fm)
        let after = InstalledModelDiscovery.readings(layout: held.layout, fileManager: held.fm)
        #expect(after.map(\.repoID) == ["mlx-community/Kept"])
        #expect(after.first?.isMLXLoadable == true)
    }
}
