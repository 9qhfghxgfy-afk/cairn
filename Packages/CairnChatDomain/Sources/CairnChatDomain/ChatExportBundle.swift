import Foundation

/// The full contents of one `.cairn` file: a marker, a version, and the chats and messages it carries.
///
/// The marker exists so a file that happens to be valid JSON — a settings dump, someone's notes — is
/// named as "not a Cairn chat" instead of decoding into an empty chat with no explanation. The version
/// exists so a file written by a future build is refused with its number rather than half-read: this app
/// promises that local data survives updates, and the only honest way to keep that promise forward in
/// time is to say plainly when a file asks for something this build cannot do.
public struct ChatExportBundle: Sendable, Equatable, Codable {
    /// The value of the file's `format` key. Checked before anything else is read.
    public static let formatMarker = "cairn.chat"
    /// The only version this build can write, and the highest it can read.
    public static let currentVersion = 1

    public var format: String
    public var version: Int
    public var exportedAt: Date
    public var chats: [ExportedChat]
    public var nodes: [ExportedNode]

    public init(
        format: String = ChatExportBundle.formatMarker,
        version: Int = ChatExportBundle.currentVersion,
        exportedAt: Date = Date(),
        chats: [ExportedChat],
        nodes: [ExportedNode]
    ) {
        self.format = format
        self.version = version
        self.exportedAt = exportedAt
        self.chats = chats
        self.nodes = nodes
    }
}

/// Why a file could not be opened, in terms that name the file rather than the failure.
public enum ChatExportIssue: LocalizedError, Equatable {
    /// Not JSON at all, or missing a required key. The reason names the key, never a fragment of content.
    case unreadable(String)
    /// Valid JSON, but its `format` is not `cairn.chat`.
    case foreignFormat(String)
    /// Written by a newer schema. The number is the file's, so the user can tell which build to use.
    case newerVersion(Int)
    /// A version this build never supported.
    case unsupportedVersion(Int)
    /// Structurally wrong: a repeated message id, a parent that is not in the file, a word in an enum
    /// field that this build does not define.
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let reason): return "That file could not be read: \(reason)."
        case .foreignFormat(let marker):
            return "That file is not a Cairn chat — it declares itself as \(marker)."
        case .newerVersion(let version):
            return "That file was written by a newer version of Cairn (format \(version)). "
                + "This build reads format \(ChatExportBundle.currentVersion)."
        case .unsupportedVersion(let version):
            return "That file uses format version \(version), which this build does not support."
        case .malformed(let reason): return "That file is not a complete Cairn chat: \(reason)."
        }
    }
}
