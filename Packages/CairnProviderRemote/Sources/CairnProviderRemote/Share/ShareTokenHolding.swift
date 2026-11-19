import CairnChatDomain
import Foundation

/// The key that opens the share surface, kept where every other credential in Cairn is kept — in a
/// Keychain namespace of its own.
///
/// A share key is a credential: anyone on the local network who holds it can spend this phone's
/// battery and the battery of any server behind it. So it goes to the Keychain with the same
/// accessibility as a server token — `.afterFirstUnlockThisDeviceOnly`, which means it does not ride
/// into an iCloud backup and cannot be read on another device restored from one. It is never written
/// to Settings, never placed in a plist, never exported with a chat, and never logged.
///
/// It is also **generated, not typed**. A key a person invents at a keyboard is a word; the surface is
/// reachable from a café router and a landlord's access point, so the default is 32 random characters
/// from the system generator and the policy refuses anything shorter than 16.
///
/// **The namespace is separate from the outbound vault on purpose.** `KeychainSecretStore`'s default
/// service holds the tokens this phone presents to *other* machines. This holder writes under
/// `shareService` instead, so rotating or clearing the inbound key is structurally incapable of
/// touching an outbound server token, and an outbound token can never be read back as the key that
/// opens this phone. Two directions of trust, two namespaces — not two comments saying so.
///
/// `@MainActor`, because that is where the vault lives: `SecretStoring` is a main-actor protocol, so a
/// holder isolated anywhere else could not reach the Keychain without an `await` in the middle of a
/// screen update. Nothing here is ever called from a socket.
@MainActor
public final class ShareTokenHolding: ShareTokenStoring {
    /// The Keychain service for the inbound key — deliberately **not** `KeychainSecretStore.defaultService`.
    public static let shareService = "app.cairn.share-key"

    /// One Keychain item for one surface. A fixed id rather than a per-profile id because there is
    /// exactly one share surface on the device; the same rule that keeps a key from being typed into a
    /// field keeps it from being scattered across records.
    static let shareTokenID = UUID(uuidString: "6d1f4b98-2f9a-4a6f-9c1e-8b2c5a7d3e40") ?? UUID()

    private let store: any SecretStoring
    private let generator: @Sendable () -> String

    /// The shipped path: the real Keychain, under the share service. `service` and `operation` are
    /// parameters rather than constants so a test can name the namespace a write landed in without a
    /// secure enclave.
    public init(
        service: String = ShareTokenHolding.shareService,
        operation: any KeychainOperating = SecurityKeychainOperator(),
        generator: @escaping @Sendable () -> String = { ShareToken.generate() }
    ) {
        self.store = KeychainSecretStore(service: service, operation: operation)
        self.generator = generator
    }

    /// A holder over an injected secret store — the seam a test uses when it wants the store itself
    /// rather than the Keychain operation behind it.
    init(store: any SecretStoring, generator: @escaping @Sendable () -> String = { ShareToken.generate() }) {
        self.store = store
        self.generator = generator
    }

    /// The stored key, or nil. Reading it never creates one: a key must not appear in the Keychain
    /// just because some screen asked what the key is.
    public func token() -> String? {
        store.secret(for: Self.shareTokenID)
    }

    /// Stores a key, or removes the item when handed an empty one. Returns whether the write held —
    /// which is the answer a caller needs, and carries no key material in it.
    @discardableResult
    public func save(_ token: String) -> Bool {
        do {
            try store.setSecret(token, for: Self.shareTokenID)
            return true
        } catch {
            // Typed truth only. `KeychainFailure` already prints just the operation and the status
            // code; nothing here adds the key that failed to land.
            return false
        }
    }

    public func clear() {
        try? store.removeSecret(for: Self.shareTokenID)
    }

    /// A new key, replacing the old. Every client configured with the previous key stops working at
    /// that moment, which is the point: this is how the user revokes a laptop, a tablet, or a key that
    /// leaked into a screenshot, without uninstalling anything.
    public func rotate() -> String {
        // Generate until the key clears the policy floor, so a weak draw can never become the key that
        // protects the surface. With a 32-character generator this loop runs once.
        for _ in 0..<8 {
            let candidate = generator()
            guard SharePolicy.tokenIsUsable(candidate) else { continue }
            // A key is only a key once the vault holds it. Handing back one the Keychain refused to
            // store would tell the user to configure a laptop with something that can never work.
            if save(candidate) { return candidate }
        }
        let fallback = ShareToken.generate()
        return save(fallback) ? fallback : ""
    }

    /// The key to start sharing with: the stored one when it still clears the policy floor, a fresh
    /// one otherwise. This is what the screen reads on first open, so a person who has never thought
    /// about a key still gets a keyed surface rather than an open one.
    public func tokenOrRotate() -> String {
        if let existing = token(), SharePolicy.tokenIsUsable(existing) { return existing }
        return rotate()
    }
}