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
}
