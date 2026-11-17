import Foundation

/// One entry in Cairn's curated on-device library.
///
/// Every field is copied from what the repository publishes. Sizes are the published totals of the
/// repo's weight files, so they are an approximation of what will land on disk; the fit estimate is
/// recomputed from the real bytes once the download finishes. Capability badges are copied, not
/// inferred — an entry with no stated capability carries no badge.
///
/// `addedToLibrary` is a fact about this file (when Cairn curated the entry), which is what the
/// "Newest" sort orders by. It is deliberately not the Hugging Face publication date, which this
/// offline catalog cannot know without a network call.
public struct OnDeviceCatalogEntry: Sendable, Equatable, Identifiable {
    public var id: String { repoID }
    /// `owner/name`, validated by `HuggingFaceRepoID`.
    public var repoID: String
    public var displayName: String
    /// Published weight bytes for the quantized MLX build.
    public var weightsBytes: Int64
    public var parameterSize: String?
    public var quantization: String?
    /// The context the model advertises, used only as the ceiling for the user's chosen length.
    public var advertisedContextLength: Int?
    /// What a phone can hold by default. Deliberately far below the advertised maximum.
    public var defaultContextLength: Int
    /// Filled from the model's own `config.json` after download; nil until then.
    public var layerCount: Int?
    public var kvHeadCount: Int?
    public var headDimension: Int?
    public var capabilities: [ModelCapability]
    public var addedToLibrary: Date

    public init(
        repoID: String,
        displayName: String,
        weightsBytes: Int64,
        parameterSize: String? = nil,
        quantization: String? = nil,
        advertisedContextLength: Int? = nil,
        defaultContextLength: Int,
        layerCount: Int? = nil,
        kvHeadCount: Int? = nil,
        headDimension: Int? = nil,
        capabilities: [ModelCapability] = [],
        addedToLibrary: Date
    ) {
        self.repoID = repoID
        self.displayName = displayName
        self.weightsBytes = weightsBytes
        self.parameterSize = parameterSize
        self.quantization = quantization
        self.advertisedContextLength = advertisedContextLength
        self.defaultContextLength = defaultContextLength
        self.layerCount = layerCount
        self.kvHeadCount = kvHeadCount
        self.headDimension = headDimension
        self.capabilities = capabilities
        self.addedToLibrary = addedToLibrary
    }

    public var weightEstimate: ModelWeightEstimate {
        ModelWeightEstimate(
            weightsBytes: weightsBytes,
            layerCount: layerCount,
            kvHeadCount: kvHeadCount,
            headDimension: headDimension
        )
    }

    /// An entry the user typed rather than picked from the library. Nothing is assumed about it:
    /// no badge, no size, and the fit estimate is whatever the files turn out to be.
    public static func unlisted(repoID: String, now: Date = Date()) -> OnDeviceCatalogEntry {
        OnDeviceCatalogEntry(
            repoID: repoID,
            displayName: repoID.split(separator: "/").last.map(String.init) ?? repoID,
            weightsBytes: 0,
            defaultContextLength: 4096,
            addedToLibrary: now
        )
    }
}
