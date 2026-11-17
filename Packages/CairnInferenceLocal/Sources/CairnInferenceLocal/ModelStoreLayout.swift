import Foundation

/// Where on-device model files live, and how they are removed.
///
/// Inside the app container, so nothing leaves the device and uninstalling the app takes the models
/// with it. The directory name is a lossy slug, which is why the repo ID itself is recorded in
/// `InstalledModelManifest` rather than reconstructed from the path.
public struct ModelStoreLayout: Sendable {
    public var rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    /// nil when the container is unavailable, which is treated as "on-device models are not
    /// offered" rather than as a crash.
    public static func defaultRoot(fileManager: FileManager = .default) -> ModelStoreLayout? {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return ModelStoreLayout(rootURL: support.appendingPathComponent("Cairn/Models", isDirectory: true))
    }

    /// Filesystem-safe, and reversible only through the stored manifest — never parsed back.
    /// Dots are dropped on purpose: a directory name must never contain `..`, even as a substring,
    /// so a hostile or accidental repo ID cannot influence path resolution.
    public static func slug(for repoID: String) -> String {
        let mapped = repoID.unicodeScalars.map { scalar -> Character in
            let isLetter = CharacterSet.alphanumerics.contains(scalar)
            let isPunctuation = "-_".unicodeScalars.contains(scalar)
            return (isLetter || isPunctuation) ? Character(scalar) : "-"
        }
        let collapsed = mapped.reduce(into: "") { partial, character in
            if character == "-", partial.last == "-" { return }
            partial.append(character)
        }
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "model" : String(trimmed.prefix(80))
    }

    public func directory(for repoID: String) -> URL {
        rootURL.appendingPathComponent(Self.slug(for: repoID), isDirectory: true)
    }

    /// Total bytes under a directory, following the directory listing rather than trusting a
    /// manifest number.
    public func sizeOnDisk(at url: URL, fileManager: FileManager = .default) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    public func install(_ repoID: String, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: directory(for: repoID), withIntermediateDirectories: true)
    }

    public func remove(_ repoID: String, fileManager: FileManager = .default) throws {
        let target = directory(for: repoID)
        guard fileManager.fileExists(atPath: target.path) else { return }
        try fileManager.removeItem(at: target)
    }

    /// Every directory that holds a model, whether or not its manifest survived.
    public func modelDirectories(fileManager: FileManager = .default) -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }
}
