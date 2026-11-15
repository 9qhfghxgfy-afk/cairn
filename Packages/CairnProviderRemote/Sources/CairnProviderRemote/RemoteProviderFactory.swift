import Foundation
import CairnChatDomain

/// Turns saved profiles into live engines, plus the tester and model-management service
/// the settings UI needs.
///
/// Disabled profiles, and public-internet profiles without the explicit opt-in, never reach
/// the engine list at all: the opt-in is enforced here rather than trusting the UI to hide
/// them.
@MainActor
public final class RemoteProviderFactory: RemoteProviderBuilding {
    private let transport: any RemoteTransport
    private let secrets: any SecretStoring

    public init(transport: any RemoteTransport = URLSessionTransport(), secrets: any SecretStoring) {
        self.transport = transport
        self.secrets = secrets
    }

    public func providers(from profiles: [ServerProfile]) -> [any InferenceProvider] {
        profiles.compactMap { profile in
            guard profile.usableNow else { return nil }
            return RemoteChatProvider(
                profile: profile,
                bearer: secrets.secret(for: profile.id),
                transport: transport
            )
        }
    }

    public func modelService() -> any RemoteModelManaging {
        RemoteModelService(transport: transport, secrets: secrets)
    }

    public func tester() -> any RemoteTesting {
        RemoteConnectionTester(transport: transport, secrets: secrets)
    }
}
