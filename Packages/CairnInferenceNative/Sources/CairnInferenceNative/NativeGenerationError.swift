import Foundation

/// Why an on-device native generation could not run, in the user's words.
///
/// Each case is a different fix, so they are not folded together: "this build has no runtime"
/// and "this model is not on disk" lead the user to completely different actions, and a single
/// generic failure would send them to neither.
public enum NativeGenerationError: Error, Equatable {
    /// Built with the runtime excluded, so there is nothing to load.
    case runtimeExcludedFromThisBuild
    /// Metal is not present, which is the simulator's normal state — not a fault to retry.
    case runtimeUnavailableOnSimulator
    /// The weights are not installed at the path this engine was given.
    case modelNotInstalled
    /// The turn has no message in it to answer — an empty transcript is not something a model can be
    /// pointed at, and pretending otherwise wastes a load of several gigabytes.
    case nothingToAnswer
    /// The runtime refused to load the weights it was given.
    case loadFailed
    /// Generation stopped partway.
    case generationFailed
    /// The caller cancelled, which is not an error worth surfacing as one.
    case cancelled

    public var message: String {
        switch self {
        case .runtimeExcludedFromThisBuild:
            return "This build of Cairn does not include the on-device MLX runtime."
        case .runtimeUnavailableOnSimulator:
            return "On-device MLX inference needs a real iPhone with Metal."
        case .modelNotInstalled:
            return "That model is not installed on this device yet."
        case .nothingToAnswer:
            return "There is no message in this turn to answer."
        case .loadFailed:
            return "The on-device runtime could not load that model."
        case .generationFailed:
            return "On-device generation stopped."
        case .cancelled:
            return "The request was cancelled."
        }
    }
}

extension NativeGenerationError: LocalizedError {
    public var errorDescription: String? { message }
}

/// Whether this build actually carries the MLX runtime.
///
/// Read from what compiled, not from a flag someone might have set: `canImport` is true only
/// when the dependency was linked, which is the fact the UI has to report.
public enum NativeRuntimeBuild {
    public static let mlxIsLinked: Bool = {
        #if canImport(MLXLLM) && canImport(MLXLMCommon)
        return true
        #else
        return false
        #endif
    }()

    public static let isSimulatorBuild: Bool = {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }()
}
