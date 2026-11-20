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

    /// One line for the Servers row: which engines are ready, or why they are not.
    public var summary: String {
        if canRunSomething {
            var ready: [String] = []
            if appleModel.isUsable { ready.append("Apple model") }
            if mlx.isUsable { ready.append("MLX") }
            let models = installedModelCount == 1 ? "1 model installed" : "\(installedModelCount) models installed"
            return "\(ready.joined(separator: " + ")) ready · \(models)"
        }
        return mlx.status
    }
}
