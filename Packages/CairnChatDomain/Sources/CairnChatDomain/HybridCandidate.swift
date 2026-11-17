import Foundation

/// One engine + model pair chosen to answer a hybrid turn.
///
/// Identity is the pair, not the engine: the same server answering with two different models
/// is two legitimate candidates, while the same engine and model twice is a mistake.
public struct HybridCandidate: Sendable, Equatable, Codable, Identifiable {
    public var engineID: String
    public var modelID: String

    public init(engineID: String, modelID: String) {
        self.engineID = engineID
        self.modelID = modelID
    }

    public var id: String { "\(engineID)|\(modelID)" }

    /// A row the user has not finished choosing. A candidate with no engine or no model
    /// cannot be sent, and sending a half-chosen name is how a server gets a model it lacks.
    public var isChosen: Bool { !engineID.isEmpty && !modelID.isEmpty }
}

/// Where a candidate could come from, as the picker sees it.
public struct HybridEngineOption: Sendable, Equatable {
    public var engineID: String
    public var modelID: String
    public var networkClass: NetworkClass

    public init(engineID: String, modelID: String, networkClass: NetworkClass) {
        self.engineID = engineID
        self.modelID = modelID
        self.networkClass = networkClass
    }

    public var isOnDevice: Bool { networkClass == .onDevice }
}