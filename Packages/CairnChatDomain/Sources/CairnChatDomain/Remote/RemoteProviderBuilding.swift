import Foundation

/// Turns saved profiles into live engines, so the server screen can add or remove a
/// remote provider and refresh the `ProviderRegistry` without rebuilding conversations.
/// Implemented in `CairnProviderRemote`; declared here so no UI imports a network module.
@MainActor
public protocol RemoteProviderBuilding: AnyObject {
    /// Disabled profiles and non-opted-in public-internet profiles produce no engine.
    func providers(from profiles: [ServerProfile]) -> [any InferenceProvider]
}
