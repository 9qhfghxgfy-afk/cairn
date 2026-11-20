import Foundation

/// One library entry the Download tab can offer — on this phone, or on a server.
///
/// This is the row shape the whole Download screen is built from, which is the reason it carries
/// both destinations: "Download to this phone" and "Download to this server" are one list with two
/// consequences, and a second row type for the second half would let the two halves drift apart in
/// a way no screen shows.
///
/// Every field is a published fact. `downloadBytes` is the publisher's stated size for the files
/// Cairn actually fetches; `capabilityLabels` are the words the publisher uses for the capabilities
/// it states, and an entry that states nothing carries no badge. `summary` is Cairn's own
/// description, written here rather than copied from a model card.
public struct LocalCatalogRow: Identifiable, Sendable, Equatable {
    /// The repository as its publisher names it — also the key the store keeps its files under. For
    /// an Ollama entry it is the exact tag the server is asked for.
    public var repoID: String
    public var displayName: String
    /// Cairn's two-line description of what this build is for.
    public var summary: String
    public var parameterSize: String?
    public var quantization: String?
    /// Bytes the publisher states for the download; nil when the entry states none, which the row
    /// shows as "size not stated" rather than as a number nobody measured.
    public var downloadBytes: Int64?
    public var contextLength: Int?
    /// The published capability names, already in the words the badges use ("Tools", "Vision").
    public var capabilityLabels: [String]
    public var addedOn: Date
    public var isInstalled: Bool
    /// Who makes the model — `Qwen`, `Google`, `OpenBMB` — as the publisher names themselves.
    public var provider: String?
    /// The family within that provider — `Qwen 3.5`, `Gemma 4`.
    public var series: String?
    /// Cairn's curated rank for the `Popular` order. Lower is earlier. Not a download counter: no
    /// request is made to any catalog service to build this screen, so a count would be invented.
    public var sortOrder: Int
    /// Which destination this entry installs to, and therefore which button is honest here.
    public var origin: ModelCatalogOrigin

    public init(
        repoID: String,
        displayName: String,
        summary: String = "",
        parameterSize: String? = nil,
        quantization: String? = nil,
        downloadBytes: Int64? = nil,
        contextLength: Int? = nil,
        capabilityLabels: [String] = [],
        addedOn: Date = Date(timeIntervalSince1970: 0),
        isInstalled: Bool = false,
        provider: String? = nil,
        series: String? = nil,
        sortOrder: Int = 0,
        origin: ModelCatalogOrigin = .onDevice
    ) {
        self.repoID = repoID
        self.displayName = displayName
        self.summary = summary
        self.parameterSize = parameterSize
        self.quantization = quantization
        self.downloadBytes = downloadBytes
        self.contextLength = contextLength
        self.capabilityLabels = capabilityLabels
        self.addedOn = addedOn
        self.isInstalled = isInstalled
        self.provider = provider
        self.series = series
        self.sortOrder = sortOrder
        self.origin = origin
    }

    public var id: String { repoID }

    /// True when every capability asked for is one this entry states. An empty request keeps
    /// everything: no chips down means no filter was applied.
    public func covers(_ required: Set<ModelCatalogCapability>) -> Bool {
        guard !required.isEmpty else { return true }
        let stated = Set(capabilityLabels)
        return required.allSatisfy { stated.contains($0.label) }
    }

    /// The same entry with the installed answer refreshed, so a list keeps its order and its
    /// metadata while one download lands.
    public func marking(installed: Bool) -> LocalCatalogRow {
        var copy = self
        copy.isInstalled = installed
        return copy
    }

    /// `Series · Provider`, or whichever half exists. Both are published names; neither is inferred,
    /// so a row that publishes neither shows neither.
    public var lineage: String {
        switch (series, provider) {
        case (let series?, let provider?): return "\(series) · \(provider)"
        case (let series?, nil): return series
        case (nil, let provider?): return provider
        case (nil, nil): return ""
        }
    }

    /// What the detail sheet draws where a capability badge would go, for an entry that publishes no
    /// capability at all. Empty when the entry does publish one — the sheet draws badges then, not words.
    ///
    /// The old line was a flat "No capabilities published for this entry", which reads like missing data
    /// on an entry that states its size, its quantisation and a context ceiling — so the person concludes
    /// the screen is broken rather than that the publisher said nothing. The line names the facts that
    /// **are** published instead, and only an entry with nothing published at all (a typed repository, a
    /// tag no server describes) says so plainly.
    ///
    /// Nothing here is inferred. A capability Cairn has not been told about is never named, because a
    /// badge a user acts on has to be a fact rather than a guess from a model's name.
    public var capabilityNote: String {
        guard capabilityLabels.isEmpty else { return "" }
        var facts: [String] = []
        if let parameterSize { facts.append(parameterSize) }
        if let quantization { facts.append(quantization) }
        if let contextLength { facts.append("\(contextLength) token context") }
        if !facts.isEmpty { return "No capability badges published · " + facts.joined(separator: " · ") }
        // Nothing published at all, which is a different sentence for each kind of entry: a repository
        // that describes none of its builds, a tag a server has no metadata for, and a name this library
        // has never heard of are three different reasons to be silent.
        switch origin {
        case .onDevice:
            return "The repository publishes nothing about this build, so nothing is claimed here."
        case .ollamaLibrary:
            return "The server publishes nothing about this tag, so nothing is claimed here."
        case .custom:
            return "That name is not in Cairn's library, so nothing is claimed about it here."
        }
    }
}
