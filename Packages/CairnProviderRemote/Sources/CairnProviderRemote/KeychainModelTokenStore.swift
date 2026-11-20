import Foundation
import CairnChatDomain

/// `ModelTokenStoring` backed by the Keychain, in a service of its own.
///
/// A separate service from the one that holds server tokens, for the same reason the share key has one:
/// these are credentials this phone *presents* to third-party services, and a lookup by profile id can
/// never return one of them by accident. The account name is the token kind's stable half, so a rename of
/// a display name cannot strand a saved token.
///
/// A struct, because the read happens on the download task rather than on the main actor and the Keychain
/// API is thread-safe. A failed read is reported as "no token", never as a message: a Keychain status
/// carries no useful words for a person, and the failure is indistinguishable from an absent item in the
/// one place it matters — the request simply goes out unauthenticated, which is what a public download
/// always looks like.
public struct KeychainModelTokenStore: ModelTokenStoring {
    /// Default service name; the app can namespace it per build (debug vs release).
    public static let defaultService = "app.cairn.model-token"

    private let operation: any KeychainOperating
    private let service: String

    public init(
        service: String = KeychainModelTokenStore.defaultService,
        operation: any KeychainOperating = SecurityKeychainOperator()
    ) {
        self.service = service
        self.operation = operation
    }

    public func token(for kind: ModelTokenKind) -> String? {
        guard let data = try? operation.data(for: query(kind)),
              let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value
    }

    /// Saves, or removes when the field was left empty. A person who clears a token and presses Save means
    /// "take it off this phone", and a write that stores an empty string would leave the row claiming a
    /// saved token that cannot authenticate anything.
    @discardableResult
    public func save(_ token: String, for kind: ModelTokenKind) -> Bool {
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return remove(kind) }
        do {
            try operation.set(query(kind), value: Data(value.utf8))
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    public func remove(_ kind: ModelTokenKind) -> Bool {
        (try? operation.remove(query(kind))) != nil
    }

    private func query(_ kind: ModelTokenKind) -> KeychainQuery {
        KeychainQuery(service: service, account: kind.storageAccount)
    }
}
