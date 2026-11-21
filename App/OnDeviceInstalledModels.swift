import Foundation
import CairnChatDomain
import CairnInferenceLocal
import CairnInferenceNative

/// What this phone holds, read once, for the two questions that get asked about it.
///
/// Three places used to read the model store for themselves and give three different answers: the Installed
/// tab listed a folder from its manifest, the MLX engine asked for a manifest *plus* `config.json` *plus*
/// weights, and the Servers row asked for nothing at all and so reported `0 models installed` whatever was
/// on disk. A phone with three downloaded models could therefore be told it had none, and the chat picker
/// could name a single model that described none of the three.
///
/// This is the one reading. It is here rather than in `CairnInferenceLocal` because the two questions it
/// answers need two modules' knowledge: the folder's files, which the local package owns, and the curated
/// display name plus the runtime the engine needs, which belong to the app that wires them together.
///
/// The distinction the screens keep asking for is preserved rather than flattened:
///
/// * **installed** — any finished folder, whatever runtime its files describe. This is what Servers counts,
///   and it does not depend on the MLX runtime having been linked into this build, which is why a
///   simulator-style build can still tell the truth about the disk;
/// * **loadable here** — the installed folders carrying `config.json` and at least one `.safetensors`, which
///   is what the MLX engine is handed as its picker.
enum OnDeviceInstalledModels {

    /// Every finished folder, newest first.
    static func readings(fileManager: FileManager = .default) -> [InstalledModelReading] {
        guard let layout = ModelStoreLayout.defaultRoot(fileManager: fileManager) else { return [] }
        return InstalledModelDiscovery.readings(layout: layout, fileManager: fileManager)
    }

    /// The folders this runtime can load, in the shape the engine asks for.
    ///
    /// Sizes are measured from the folder rather than taken from the manifest: iOS can purge weights, and
    /// the number a memory gate prices a load from has to be the number of bytes actually here.
    static func mlxLoadableFolders(fileManager: FileManager = .default) -> [NativeInstalledModel] {
        guard let layout = ModelStoreLayout.defaultRoot(fileManager: fileManager) else { return [] }
        return InstalledModelDiscovery.mlxLoadable(layout: layout, fileManager: fileManager)
            .map { folder in
                NativeInstalledModel(
                    id: folder.repoID,
                    displayName: displayName(for: folder.repoID),
                    directoryURL: folder.directoryURL,
                    format: .mlx,
                    sizeBytes: layout.sizeOnDisk(at: folder.directoryURL, fileManager: fileManager)
                )
            }
    }

    /// What the Servers row says this phone holds — every finished folder, whatever runtime it describes.
    static func installedCount(fileManager: FileManager = .default) -> Int {
        readings(fileManager: fileManager).count
    }

    /// The curated name when Cairn knows this repository, the repository id when it does not. No friendlier
    /// name is invented for something nobody curated.
    private static func displayName(for repoID: String) -> String {
        ModelCatalog.onDevice.first { $0.repoID == repoID }?.displayName ?? repoID
    }
}
