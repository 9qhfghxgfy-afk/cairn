import Foundation
import CairnChatDomain

/// `SecretStoring` backed by the Keychain.
///
/// The settings store never sees a token, so it cannot accidentally persist one: the
/// profile record holds a profile id, and the id is only ever a Keychain account name.
@MainActor
public final class KeychainSecretStore: SecretStoring {
    /// Default service name; the app can namespace it per build (debug vs release).
    public static let defaultService = "app.cairn.server-token"

    private let operation: any KeychainOperating
    private let service: String

    public init(service: String = KeychainSecretStore.defaultService, operation: any KeychainOperating = SecurityKeychainOperator()) {
        self.service = service
        self.operation = operation
    }

    public func setSecret(_ secret: String, for profileID: UUID) throws {
        let query = KeychainQuery(service: service, account: profileID.uuidString)
        guard !secret.isEmpty else {
            try operation.remove(query)
            return
        }
        try operation.set(query, value: Data(secret.utf8))
    }

    public func secret(for profileID: UUID) -> String? {
        let query = KeychainQuery(service: service, account: profileID.uuidString)
        guard let data = try? operation.data(for: query) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func removeSecret(for profileID: UUID) throws {
        try operation.remove(KeychainQuery(service: service, account: profileID.uuidString))
    }
}
