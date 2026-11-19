import Foundation

/// One model this phone offers to another machine.
///
/// The served **name is the engine id**, deliberately: a client asking for `cairn-foundation`
/// gets the engine with that id and nothing else, so there is no alias table to get out of sync
/// and no way for one name to quietly resolve to a server the user never selected.
public struct ShareModelEntry: Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var engineID: String
    public var parameterSize: String?
    public var quantization: String?
    public var contextLength: Int?

    public init(
        id: String,
        displayName: String,
        engineID: String,
        parameterSize: String? = nil,
        quantization: String? = nil,
        contextLength: Int? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.engineID = engineID
        self.parameterSize = parameterSize
        self.quantization = quantization
        self.contextLength = contextLength
    }
}

/// What the surface may answer with, fixed at the moment sharing starts.
///
/// A snapshot rather than a live view of the registry: turning sharing on is the opt-in, and the
/// set it serves is the set that was agreed to at that moment. Add a server profile afterwards and
/// the surface keeps serving what it was started with, because silently starting to serve a new
/// engine to the LAN would be an outbound path the user never switched on.
public struct ShareEngineTable: Sendable {
    public private(set) var entries: [ShareModelEntry]
    private var providers: [String: any InferenceProvider]

    public init(entries: [ShareModelEntry] = [], providers: [String: any InferenceProvider] = [:]) {
        self.entries = entries
        self.providers = providers
    }

    public var servedIDs: [String] { entries.map(\.id) }
    public var isEmpty: Bool { entries.isEmpty }

    public func provider(forModelID id: String) -> (any InferenceProvider)? { providers[id] }
    public func entry(forModelID id: String) -> ShareModelEntry? {
        entries.first { $0.id == id }
    }

    /// Selection order is kept, so the list a client sees is the list the user ticked.
    /// An id that names no live engine is dropped rather than served as a ghost.
    public static func build(from engines: [any InferenceProvider], selected: [String]) -> ShareEngineTable {
        var entries: [ShareModelEntry] = []
        var providers: [String: any InferenceProvider] = [:]
        for id in selected {
            guard let engine = engines.first(where: { $0.id == id }) else { continue }
            guard providers[engine.id] == nil else { continue }
            entries.append(ShareModelEntry(id: engine.id, displayName: engine.displayName, engineID: engine.id))
            providers[engine.id] = engine
        }
        return ShareEngineTable(entries: entries, providers: providers)
    }
}
