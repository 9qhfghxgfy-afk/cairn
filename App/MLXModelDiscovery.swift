import Foundation
import CairnInferenceLocal

/// Finds an installed MLX model folder in the app's own model store.
///
/// The store is written by `ModelDownloadManager` and read here, so a model that finishes downloading
/// while Cairn is open is ready on the next look rather than on the next launch — which is the whole
/// point of installing a model on a phone: you want to use it straight away.
///
/// A folder counts as loadable only when three things are present:
/// * `cairn-install.json`, written last by the installer, so a half-finished download is never offered
///   to a runtime as a model it can load;
/// * `config.json`, which is what tells the runtime the architecture;
/// * at least one `.safetensors` weight file.
enum MLXModelDiscovery {
    static func installedDirectory(fileManager: FileManager = .default) -> URL? {
        installedEntries(fileManager: fileManager).first?.url
    }

    /// Every loadable folder, newest first, so a phone holding two builds loads the one it got last —
    /// the same rule the Installed list uses when it orders what is on disk.
    private static func installedEntries(
        fileManager: FileManager
    ) -> [(url: URL, stamp: Date)] {
        guard let layout = ModelStoreLayout.defaultRoot(fileManager: fileManager) else { return [] }
        let found = layout.modelDirectories(fileManager: fileManager).compactMap { directory -> (URL, Date)? in
            guard isLoadable(directory, fileManager: fileManager) else { return nil }
            return (directory, modificationDate(of: directory, fileManager: fileManager))
        }
        return found.sorted { $0.1 > $1.1 }
    }

    private static func isLoadable(_ directory: URL, fileManager: FileManager) -> Bool {
        guard fileManager.fileExists(atPath: directory.appendingPathComponent("cairn-install.json").path),
              fileManager.fileExists(atPath: directory.appendingPathComponent("config.json").path)
        else { return false }
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return false }
        return names.contains { $0.hasSuffix(".safetensors") }
    }

    /// The folder's own write time. A missing reading sorts last rather than becoming "now", because a
    /// guess about which model is newer is a guess about which model the phone will run.
    private static func modificationDate(of url: URL, fileManager: FileManager) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? Date(timeIntervalSince1970: 0)
    }

    /// What loading this folder would cost the process, read from the files themselves.
    ///
    /// The catalogue's advertised size is not used: a download can be interrupted, resumed or partially
    /// deleted, and the only figure that describes what this phone is about to allocate is the number of
    /// bytes actually sitting in the folder. The attention shape comes from the model's own
    /// `config.json`, and a field the model never published stays `nil` — the preflight then charges a
    /// blanket reserve instead of inventing an architecture.
    ///
    /// `nil` means unmeasurable: the folder is not loadable, or its size cannot be read. The gate treats
    /// that as a refusal rather than as a zero, because "we could not tell" is not a licence to allocate.
    static func footprint(
        at directory: URL,
        fileManager: FileManager = .default
    ) -> MLXModelFootprint? {
        guard isLoadable(directory, fileManager: fileManager),
              let layout = ModelStoreLayout.defaultRoot(fileManager: fileManager)
        else { return nil }
        let weights = layout.sizeOnDisk(at: directory, fileManager: fileManager)
        guard weights > 0 else { return nil }

        let configURL = directory.appendingPathComponent("config.json")
        var facts = ModelConfigFacts()
        if let data = try? Data(contentsOf: configURL) {
            facts = ModelConfigReader.read(data)
        }
        return MLXModelFootprint(
            weightsBytes: weights,
            layerCount: facts.layerCount,
            kvHeadCount: facts.kvHeadCount,
            headDimension: facts.headDimension
        )
    }
}

/// One model folder's cost, as far as this app can measure it.
///
/// Sizes and architecture numbers only — no repo name, no path, nothing that identifies which model a
/// person downloaded. That is deliberate: this value travels into a memory decision, and a memory
/// decision needs numbers, not a name.
struct MLXModelFootprint: Sendable, Equatable {
    var weightsBytes: Int64
    var layerCount: Int?
    var kvHeadCount: Int?
    var headDimension: Int?
}
