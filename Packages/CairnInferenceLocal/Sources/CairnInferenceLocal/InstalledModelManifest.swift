import Foundation

/// One file belonging to an installed model, with the digest it was verified against.
public struct InstalledModelFile: Sendable, Equatable, Codable {
    public var name: String
    public var bytes: Int64
    public var sha256: String?

    public init(name: String, bytes: Int64, sha256: String?) {
        self.name = name
        self.bytes = bytes
        self.sha256 = sha256
    }
}

/// What Cairn recorded when a model finished downloading.
///
/// Stored as JSON next to the weights. The repo ID has to be written down because the directory
/// name is a lossy slug, and the digests have to be written down because re-verification after a
/// resume or an OS-level purge is the only way to tell a complete model from a truncated one.
public struct InstalledModelManifest: Sendable, Equatable, Codable, Identifiable {
    public var id: String { repoID }
    public var repoID: String
    public var installedAt: Date
    public var files: [InstalledModelFile]

    public init(repoID: String, installedAt: Date, files: [InstalledModelFile]) {
        self.repoID = repoID
        self.installedAt = installedAt
        self.files = files
    }

    public var totalBytes: Int64 {
        files.reduce(Int64(0)) { $0.addingReportingOverflow($1.bytes).partialValue }
    }

    /// The file that says a folder is finished. Written last by the installer, so its presence is the
    /// difference between "bytes are arriving" and "this model is installed".
    public static let manifestFileName = "cairn-install.json"

    public var manifestFileName: String { Self.manifestFileName }

    public func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(self)
    }

    public static func decode(_ data: Data) -> InstalledModelManifest? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(InstalledModelManifest.self, from: data)
    }

    /// Every recorded file that has a digest, so a re-verification pass skips files the publisher
    /// never published a digest for instead of failing on them.
    public var verifiableFiles: [InstalledModelFile] {
        files.filter { ($0.sha256?.isEmpty == false) }
    }
}
