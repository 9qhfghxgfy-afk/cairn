import Foundation

/// Where a paused download's resume block is kept.
///
/// The block belongs next to the model, not in user defaults: it is opaque transfer state, it is
/// useless once the file verifies, and it must go away when the model is deleted.
public struct ModelResumeStore: Sendable {
    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func forStore(_ layout: ModelStoreLayout) -> ModelResumeStore {
        ModelResumeStore(directory: layout.rootURL.appendingPathComponent(".resume", isDirectory: true))
    }

    public func url(repoID: String, file: String) -> URL? {
        guard HuggingFaceEndpoints.isSafeFileName(file) else { return nil }
        let fileKey = ModelStoreLayout.slug(for: file)
        return directory
            .appendingPathComponent(ModelStoreLayout.slug(for: repoID), isDirectory: true)
            .appendingPathComponent(fileKey)
    }

    public func save(_ data: Data, repoID: String, file: String) {
        guard let target = url(repoID: repoID, file: file) else { return }
        try? FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: target, options: .atomic)
    }

    public func load(repoID: String, file: String) -> Data? {
        guard let source = url(repoID: repoID, file: file) else { return nil }
        return try? Data(contentsOf: source)
    }

    public func clear(repoID: String, file: String) {
        guard let target = url(repoID: repoID, file: file) else { return }
        try? FileManager.default.removeItem(at: target)
    }

    /// Called when a model is deleted or fully installed, so a stale block can never shorten a
    /// later download of the same name.
    public func clearAll(repoID: String) {
        let target = directory.appendingPathComponent(ModelStoreLayout.slug(for: repoID), isDirectory: true)
        try? FileManager.default.removeItem(at: target)
    }
}
