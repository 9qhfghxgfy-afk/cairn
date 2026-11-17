import Foundation

/// Which on-device runtime holds a model. `appleFoundationModels` is system-managed: nothing is
/// downloaded through it and nothing is unloaded by Cairn, so it appears in the Running tab as
/// information rather than as something this app controls.
public enum OnDeviceRuntime: String, Sendable, Equatable, CaseIterable, Codable {
    case appleFoundationModels
    case mlx

    public var displayName: String {
        switch self {
        case .appleFoundationModels: return "Apple Foundation Models"
        case .mlx: return "MLX"
        }
    }

    /// Only MLX models are downloaded and deleted by Cairn; Apple's model is installed by the OS.
    public var lifecycleIsOurs: Bool { self == .mlx }
}

/// One model currently resident in this process.
public struct ResidentModel: Sendable, Equatable, Identifiable {
    public var id: String { modelID }
    public var modelID: String
    public var runtime: OnDeviceRuntime
    /// Bytes the model's own files occupy on disk.
    public var weightsBytes: Int64
    /// Weights + attention cache for the context this model is loaded with.
    public var footprintBytes: Int64
    public var contextLength: Int

    public init(
        modelID: String,
        runtime: OnDeviceRuntime,
        weightsBytes: Int64,
        footprintBytes: Int64,
        contextLength: Int
    ) {
        self.modelID = modelID
        self.runtime = runtime
        self.weightsBytes = weightsBytes
        self.footprintBytes = footprintBytes
        self.contextLength = contextLength
    }
}
