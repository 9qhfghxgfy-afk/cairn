import Foundation

/// What the Model Manager and the Servers row are allowed to promise about the native runtime.
///
/// This is derived, never asserted. Three separate conditions have to hold before a load may be
/// offered, and each one has a different remedy, so they stay separate here and the UI reads
/// `reasonText` verbatim.
public enum NativeRuntimeAvailability: Equatable, Sendable {
    case ready
    case excludedFromThisBuild
    case unavailableOnSimulator
    case noModelInstalled

    public var isUsable: Bool { self == .ready }

    public var reasonText: String {
        switch self {
        case .ready: return "On-device MLX runtime available"
        case .excludedFromThisBuild:
            return "This build of Cairn does not include the on-device MLX runtime"
        case .unavailableOnSimulator:
            return "On-device MLX inference needs a real iPhone with Metal"
        case .noModelInstalled:
            return "No on-device model installed yet"
        }
    }

    /// Short form for the Servers row, where there is one line and no room for prose.
    public var shortLabel: String {
        switch self {
        case .ready: return "MLX ready"
        case .excludedFromThisBuild: return "MLX not in this build"
        case .unavailableOnSimulator: return "MLX unavailable here"
        case .noModelInstalled: return "MLX idle"
        }
    }

    /// Reads the build's own compiled state plus what the caller knows is on disk. Nothing is
    /// probed against Metal here: that would need a real device, and a guess about a GPU this
    /// machine does not have is exactly the kind of fact Cairn does not assert.
    public static func current(hasInstalledModel: Bool) -> NativeRuntimeAvailability {
        if !NativeRuntimeBuild.mlxIsLinked { return .excludedFromThisBuild }
        if NativeRuntimeBuild.isSimulatorBuild { return .unavailableOnSimulator }
        if !hasInstalledModel { return .noModelInstalled }
        return .ready
    }
}
