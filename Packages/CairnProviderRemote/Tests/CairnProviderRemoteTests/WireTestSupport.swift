import Foundation
import CairnChatDomain
@testable import CairnProviderRemote

/// Shared fixtures for the two wire-level suites. The profiles are the two kinds P1 added, and the
/// secret store is the real `KeychainSecretStore` over a fake operator, so a test can prove a token
/// travels without touching the real Keychain.
@MainActor
enum WireFixtures {
    /// A box on the user's own network, addressed over plain http — the supported LAN route.
    static var studio: ServerProfile {
        ServerProfile(name: "Studio box", kind: .lmStudio, baseURLString: "http://192.168.1.10:1234")
    }

    static var cloud: ServerProfile {
        ServerProfile(name: "Ollama Cloud", kind: .ollamaCloud, baseURLString: "https://ollama.com")
    }

    /// The same profile after the user has turned it on and allowed traffic to leave the device.
    static var optedInCloud: ServerProfile {
        var profile = cloud
        profile.enabled = true
        profile.publicInternetOptIn = true
        profile.hasBearerToken = true
        return profile
    }

    static func secrets() -> KeychainSecretStore { KeychainSecretStore(operation: FakeKeychainOperator()) }
}
