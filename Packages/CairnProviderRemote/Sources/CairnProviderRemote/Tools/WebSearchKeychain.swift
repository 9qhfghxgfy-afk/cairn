import Foundation
import CairnChatDomain

/// The Keychain service that holds search-provider credentials.
///
/// A separate service from the server-profile token store, on purpose. A SearXNG instance's token is not a
/// model server's token, and sharing one vault would mean a search row could be handed a server's bearer
/// token by accident — or, worse, a server's token could be sent to a search endpoint because two records
/// live in the same place. Different services, different account namespaces, no path from one to the other.
///
/// The access class is `.afterFirstUnlockThisDeviceOnly`, like every other secret here: readable while the
/// device is unlocked, never copied to another device, and never in a backup that leaves it.
@MainActor
public enum WebSearchKeychain {
    public static let service = "app.cairn.websearch"

    /// The vault, keyed by **provider row id** — the row is the account name, and the row never holds the
    /// value, so a settings export cannot carry a token.
    public static func store(operation: any KeychainOperating = SecurityKeychainOperator()) -> KeychainSecretStore {
        KeychainSecretStore(service: service, operation: operation)
    }
}
