import Foundation

/// Which runtime a model in the Installed section runs on, and therefore what badge it carries.
///
/// The badge is the only thing that tells a person why two rows with the same model name are not the
/// same model: an MLX build on this iPhone and the same family pulled onto a LAN server are different
/// bytes on different machines, and a list that showed only names would read as a duplicate.
///
/// Every case is a fact about where the bytes are and who can run them. Nothing here is guessed from a
/// model's name — `detect(fileNames:)` reads the files that are actually in the folder.
public enum ModelFormat: String, Sendable, Equatable, CaseIterable {
    /// MLX weights in Cairn's own model store, run by the on-device MLX runtime.
    case mlx
    /// GGUF weights in Cairn's own model store.
    case gguf
    /// Apple's system model. Installed, updated and evicted by iOS, never by Cairn.
    case appleIntelligence
    /// A model a server reports about itself. Cairn did not put it there.
    case server
    /// On this phone, but its files do not name a runtime Cairn recognises.
    case other

    public var badgeText: String {
        switch self {
        case .mlx: return "MLX"
        case .gguf: return "GGUF"
        case .appleIntelligence: return "Apple Intelligence"
        case .server: return "Server"
        case .other: return "Local"
        }
    }

    /// The runtime a folder's file names describe, or nil when they describe none.
    ///
    /// GGUF is checked first: a repository that carries both a `.gguf` copy and `.safetensors` shards is
    /// offering the same model in two shapes, and the GGUF file is what a GGUF download asked for. A
    /// folder with neither is not a model this app can run, so the answer is nil rather than a guess.
    public static func detect(fileNames: [String]) -> ModelFormat? {
        var extensions: Set<String> = []
        for name in fileNames {
            guard let dot = name.lastIndex(of: ".") else { continue }
            let ext = String(name[name.index(after: dot)...]).lowercased()
            if !ext.isEmpty { extensions.insert(ext) }
        }
        if extensions.contains("gguf") { return .gguf }
        if extensions.contains("safetensors") { return .mlx }
        return nil
    }
}

/// Whose machine holds the bytes an Installed row describes.
///
/// This is the fact that decides whether a Delete button may exist at all. Cairn removes what it put on
/// this phone; it does not remove what iOS installed, and it does not remove what a server installed.
public enum ModelHost: String, Sendable, Equatable {
    /// This iPhone, in Cairn's own model store.
    case thisPhone
    /// This iPhone, managed by iOS.
    case system
    /// Somebody else's machine, named by its profile.
    case remoteServer

    /// Whether Cairn may take these bytes back.
    ///
    /// Two of the three hosts are honest "no"s: Apple's model is evicted by iOS and a server's models
    /// belong to that server. Only bytes this app wrote to this device are Cairn's to delete.
    public var lifecycleIsOurs: Bool { self == .thisPhone }

    public var sourceText: String {
        switch self {
        case .thisPhone: return "On this iPhone"
        case .system: return "Built-in"
        case .remoteServer: return "On a server"
        }
    }
}

/// One model the Installed section can show, wherever its bytes live.
///
/// The Installed section has had exactly one source since it was written — the server that happens to be
/// open — which is why a phone with four models on disk and no server configured shows an empty tab.
/// This is the shape that lets three sources share one list without lying about each other:
///
/// * `id` is **name-spaced by host**, so a LAN tag called `qwen3:4b` and a folder called `qwen3:4b` are
///   two entries with two ids, and neither overwrites the other;
/// * `canDelete` is derived rather than stored, so nobody can build an Apple Intelligence row that
///   offers to delete the system model;
/// * `sizeBytes` is a measured reading or nil — the row prints "size not measured" rather than a number
///   nobody read.
public struct InstalledModelEntry: Identifiable, Sendable, Equatable {
    public var id: String
    public var displayName: String
    public var format: ModelFormat
    public var host: ModelHost
    /// The identifier **the host itself** uses for these bytes: the repository id for a folder on this
    /// phone, the tag a server published for a remote model, nil for the system model.
    ///
    /// `id` is name-spaced so two hosts can hold one name without colliding, which makes it useless for
    /// talking back to the host that owns the row. Deleting a folder and asking a server about a tag both
    /// need the un-prefixed value, and reconstructing it by cutting a prefix off `id` would tie every
    /// caller to today's prefix spelling.
    public var hostModelID: String?
    /// The machine that reported the entry, in its own words: the server profile's name. Nil for the
    /// phone and the system model, which need no further naming.
    public var sourceName: String?
    /// Bytes on disk, measured from the folder rather than from a publisher's stated figure.
    public var sizeBytes: Int64?
    public var fileCount: Int?
    public var installedOn: Date?
    /// The reporting source's own sentence — Apple's availability reason, a server's parameter size.
    public var detail: String?

    public init(
        id: String,
        displayName: String,
        format: ModelFormat,
        host: ModelHost,
        hostModelID: String? = nil,
        sourceName: String? = nil,
        sizeBytes: Int64? = nil,
        fileCount: Int? = nil,
        installedOn: Date? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.format = format
        self.host = host
        self.hostModelID = hostModelID
        self.sourceName = sourceName
        self.sizeBytes = sizeBytes
        self.fileCount = fileCount
        self.installedOn = installedOn
        self.detail = detail
    }

    /// Apple's model is installed and evicted by iOS, so it is information in this list rather than a
    /// thing this app owns.
    public var isSystemManaged: Bool { format == .appleIntelligence || host == .system }

    /// Whether a Delete control may be drawn. Derived on purpose: the invariant that the built-in model
    /// has no delete button has to hold even when a caller builds an entry by hand.
    public var canDelete: Bool { host.lifecycleIsOurs && !isSystemManaged }

    /// The badge every row carries, so a merged list always says which runtime a model runs on.
    public var badgeText: String { format.badgeText }

    /// The sub-line under the name: the source's own words, falling back to the host's.
    public var sourceLine: String { sourceName ?? host.sourceText }

    // MARK: - Name-spaced identifiers

    /// A folder on this phone, keyed by the repository id the manifest recorded.
    public static func phoneID(repoID: String) -> String { "phone:" + repoID }

    /// The built-in system model — exactly one row, whatever a server lists.
    public static let systemID = "system:apple-intelligence"

    /// One tag on one server, keyed by both, so two servers holding the same tag stay two rows.
    public static func serverID(profileID: String, modelID: String) -> String {
        "server:\(profileID):\(modelID)"
    }
}
