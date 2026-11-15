import Foundation
import Observation

/// Live provider list shared by the workspace and its sessions, so the server
/// profiles screen can add or remove remote engines without rebuilding views
/// or re-creating conversations.
@Observable @MainActor
public final class ProviderRegistry {
    public private(set) var providers: [any InferenceProvider]

    public init(providers: [any InferenceProvider] = []) {
        self.providers = providers
    }

    public func update(_ newProviders: [any InferenceProvider]) {
        providers = newProviders
    }

    public func provider(id: String) -> (any InferenceProvider)? {
        providers.first { $0.id == id }
    }

    public var ids: [String] { providers.map(\.id) }

    public func displayName(for id: String) -> String {
        provider(id: id)?.displayName ?? id
    }
}