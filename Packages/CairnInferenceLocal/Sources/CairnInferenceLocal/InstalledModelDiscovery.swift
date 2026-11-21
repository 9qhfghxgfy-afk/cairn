import Foundation

/// One installed model folder, as the store reports it.
///
/// This is a *reading*, not a decision: it says what a folder is, and every caller above decides what to
/// do with it. `isMLXLoadable` is carried rather than inferred by each caller because the three things MLX
/// needs — the install manifest, `config.json`, and at least one weight file — are exactly the things read
/// here, and a second copy of that rule in a second file is how a screen starts disagreeing with the engine
/// about whether a model exists.
public struct InstalledModelReading: Sendable, Equatable {
    public var repoID: String
    public var directoryURL: URL
    /// The file names the manifest recorded, which is what this phone was actually given.
    public var fileNames: [String]
    public var fileCount: Int
    /// Bytes the manifest says it wrote. Callers measure the folder when they need the current number —
    /// iOS can purge weights, and a manifest figure is a record of a moment, not a reading.
    public var manifestBytes: Int64
    public var installedOn: Date
    public var isMLXLoadable: Bool

    public init(
        repoID: String,
        directoryURL: URL,
        fileNames: [String],
        fileCount: Int,
        manifestBytes: Int64,
        installedOn: Date,
        isMLXLoadable: Bool
    ) {
        self.repoID = repoID
        self.directoryURL = directoryURL
        self.fileNames = fileNames
        self.fileCount = fileCount
        self.manifestBytes = manifestBytes
        self.installedOn = installedOn
        self.isMLXLoadable = isMLXLoadable
    }
}

/// What this phone holds, read once, for everyone who asks.
///
/// There were three reads of the same folder and they did not agree. The Installed list asked only for a
/// manifest; the engine asked for a manifest *plus* `config.json` plus weights; and the Servers row asked
/// for neither and reported a count of zero whatever was on disk. So a phone with three downloaded models
/// could be told it had none, and the picker could name one model that described none of the three.
///
/// One read, one rule about what counts as installed:
///
/// * a folder with no readable `cairn-install.json` is **not** installed — the manifest is written last,
///   precisely so a partial download is never offered as a model;
/// * everything with a manifest is listed, whatever runtime its files describe, so a GGUF folder is
///   counted on a phone even in a build that left the MLX runtime out;
/// * the MLX subset is marked rather than filtered, because "installed" and "loadable by this runtime" are
///   two different questions and the two screens ask them differently.
public enum InstalledModelDiscovery {

    /// Every installed folder, newest first — the order the Installed list draws and the order a phone
    /// falling back from a deleted model should land in.
    public static func readings(
        layout: ModelStoreLayout,
        fileManager: FileManager = .default
    ) -> [InstalledModelReading] {
        layout.modelDirectories(fileManager: fileManager)
            .compactMap { reading(in: $0, fileManager: fileManager) }
            .sorted { $0.installedOn > $1.installedOn }
    }

    /// The folders the MLX runtime can load, newest first.
    public static func mlxLoadable(
        layout: ModelStoreLayout,
        fileManager: FileManager = .default
    ) -> [InstalledModelReading] {
        readings(layout: layout, fileManager: fileManager)
            .filter { $0.isMLXLoadable }
    }

    /// One directory, if it is an installed model folder.
    static func reading(in directory: URL, fileManager: FileManager) -> InstalledModelReading? {
        guard let data = try? Data(
            contentsOf: directory.appendingPathComponent(InstalledModelManifest.manifestFileName)
        ), let manifest = InstalledModelManifest.decode(data) else { return nil }
        let names = manifest.files.map { $0.name }
        // Measured from the folder rather than from the manifest's list: a repository's file list is what
        // was published, the directory is what is here.
        let present = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        let hasWeights = present.contains { $0.hasSuffix(".safetensors") }
        return InstalledModelReading(
            repoID: manifest.repoID,
            directoryURL: directory,
            fileNames: names,
            fileCount: manifest.files.count,
            manifestBytes: manifest.totalBytes,
            installedOn: manifest.installedAt,
            isMLXLoadable: hasWeights
                && fileManager.fileExists(
                    atPath: directory.appendingPathComponent("config.json").path
                )
        )
    }
}
