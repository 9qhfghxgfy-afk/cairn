import Foundation

/// What one on-device engine on this phone can do right now, as reported by its own runtime.
///
/// A plain value, so the Servers screen can show the On-Device row without CairnAppUI importing
/// either runtime. The App layer reads the truth from `AppleModelAvailability` and the MLX module
/// and hands it across the boundary as data — which is also what keeps a view from ever calling a
/// provider directly.
public struct OnDeviceEngineState: Sendable, Equatable {
    public var name: String
    /// The runtime's own words, shown as returned. A status the app invented would be a promise
    /// about hardware it has not checked.
    public var status: String
    public var isUsable: Bool
    /// The engine this state describes, so a row that says "ready" can also put the chat on it.
    /// nil for a runtime with no engine registered behind it, which is reported as a status line and
    /// nothing more — a tap that routes to an engine nobody registered is the failure this avoids.
    public var engineID: String?

    public init(name: String, status: String, isUsable: Bool, engineID: String? = nil) {
        self.name = name
        self.status = status
        self.isUsable = isUsable
        self.engineID = engineID
    }
}

/// The pair of on-device engines, together with how many models are installed for them.
public struct OnDeviceEngineReport: Sendable, Equatable {
    public var appleModel: OnDeviceEngineState
    public var mlx: OnDeviceEngineState
    public var installedModelCount: Int

    public init(
        appleModel: OnDeviceEngineState,
        mlx: OnDeviceEngineState,
        installedModelCount: Int = 0
    ) {
        self.appleModel = appleModel
        self.mlx = mlx
        self.installedModelCount = installedModelCount
    }

    /// The starting point before anything has been read: nothing usable, and it says so. Never a
    /// default that looks ready.
    public static let unavailable = OnDeviceEngineReport(
        appleModel: OnDeviceEngineState(name: "Apple model", status: "Not checked yet", isUsable: false),
        mlx: OnDeviceEngineState(name: "MLX", status: "Not checked yet", isUsable: false)
    )

    public var canRunSomething: Bool { appleModel.isUsable || mlx.isUsable }

    /// The engines a chat can be pointed at right now, in the order the row shows them.
    ///
    /// Only usable ones are offered: a row that offers "use this" for a runtime the device says is
    /// not ready is a tap that fails, and a control that fails on tap is worse than no control.
    public var engineChoices: [EngineChoice] {
        [appleModel, mlx].compactMap { state in
            guard state.isUsable, let engineID = state.engineID else { return nil }
            return EngineChoice(engineID: engineID, name: state.name)
        }
    }

    /// The models half of the line, phrased for the count it describes.
    ///
    /// "0 models installed" is a sentence with no subject, and it is what the Servers row used to say to a
    /// phone holding three downloaded folders. Zero gets its own wording because that is a different fact —
    /// nothing is on this phone — not a number that happens to be small.
    private var modelPhrase: String {
        switch installedModelCount {
        case 0: return "no models installed"
        case 1: return "1 model installed"
        default: return "\(installedModelCount) models installed"
        }
    }

    /// One line for the Servers row: which engines are ready, or why they are not.
    ///
    /// The count rides along in both branches. When an engine is ready it says what can be run; when none
    /// is, the count says why the phone is not simply empty — weights are here and waiting on a runtime,
    /// which is a different thing to read than "nothing installed".
    public var summary: String {
        if canRunSomething {
            var ready: [String] = []
            if appleModel.isUsable { ready.append("Apple model") }
            if mlx.isUsable { ready.append("MLX") }
            return "\(ready.joined(separator: " + ")) ready · \(modelPhrase)"
        }
        guard installedModelCount > 0 else { return mlx.status }
        return "\(mlx.status) · \(modelPhrase)"
    }
}
