import Foundation
import CairnChatDomain

/// The key that opens the share surface, kept where every other credential in Cairn is kept.
///
/// A share key is a credential: anyone on the local network who holds it can spend this phone's
/// battery and the battery of any server behind it. So it goes to the Keychain with the same
/// accessibility as a server token — `.afterFirstUnlockThisDeviceOnly`, which means it does not ride
/// into an iCloud backup and cannot be read on another device restored from one. It is never written
/// to Settings, never placed in a plist, never exported with a chat, and never logged.
///
/// It is also **generated, not typed**. A key a person invents at a keyboard is a word; the surface
/// is reachable from a café router and a landlord's access point, so the default is 32 random
/// characters from the system generator and the policy refuses anything shorter than 16.
public actor ShareTokenHolding {
    /// One Keychain item for one surface. A fixed id rather than a per-profile id because there is
    /// exactly one share surface on the device; the same rule that keeps a token from being typed
    /// into a field keeps it from being scattered across records.
    static let shareTokenID = UUID(uuidString: "6d1f4b98-2f9a-4a6f-9c1e-8b2c5a7d3e40") ?? UUID()

    private let store: any SecretStoring
    private let generator: @Sendable () -> String

    public init(
        store: any SecretStoring = KeychainSecretStore(),
        generator: @escaping @Sendable () -> String = { ShareToken.generate() }
    ) {
        self.store = store
        self.generator = generator
    }

    /// The stored key, or nil. Reading it never creates one: a key must not appear in the Keychain
    /// just because some screen asked what the key is.
    public func current() -> String? {
        store.secret(for: Self.shareTokenID)
    }

    /// The key to start with: the stored one if there is one, a fresh one otherwise.
    public func currentOrGenerate() -> String {
        if let existing = current(), SharePolicy.tokenIsUsable(existing) { return existing }
        return rotate()
    }

    /// A new key, replacing the old. Every client that was configured with the previous key stops
    /// working at that moment, which is the point: this is how the user revokes a laptop, a tablet,
    /// or a key that leaked into a screenshot without uninstalling anything.
    public func rotate() -> String {
        // Generate until the key clears the policy floor, so a weak draw can never become the key
        // that protects the surface. With a 32-character generator this loop runs once.
        for _ in 0..<8 {
            let candidate = generator()
            if SharePolicy.tokenIsUsable(candidate) {
                try? store.setSecret(candidate, for: Self.shareTokenID)
                return candidate
            }
        }
        let fallback = ShareToken.generate()
        try? store.setSecret(fallback, for: Self.shareTokenID)
        return fallback
    }

    public func clear() {
        try? store.removeSecret(for: Self.shareTokenID)
    }
}
