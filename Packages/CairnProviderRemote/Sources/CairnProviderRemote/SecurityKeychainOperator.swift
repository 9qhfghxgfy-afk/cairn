import Foundation
import Security

/// The real Keychain: one generic-password item per profile in the data-protection
/// keychain, accessible only after the first unlock and never synced to another device.
///
/// This is the only place in the app that touches Security.framework, and the only thing
/// that ever holds a server token.
public struct SecurityKeychainOperator: KeychainOperating {
    public init() {}

    private func attributes(_ query: KeychainQuery) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: query.service,
            kSecAttrAccount as String: query.account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    public func set(_ query: KeychainQuery, value: Data) throws {
        let item = attributes(query)
        let updated = SecItemUpdate(item as CFDictionary, [kSecValueData as String: value] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw KeychainFailure(operation: "update", status: updated) }

        var added = item
        added[kSecValueData as String] = value
        added[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(added as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainFailure(operation: "add", status: status) }
    }

    public func data(for query: KeychainQuery) throws -> Data? {
        var item = attributes(query)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainFailure(operation: "copy", status: status) }
        return result as? Data
    }

    public func remove(_ query: KeychainQuery) throws {
        let status = SecItemDelete(attributes(query) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainFailure(operation: "delete", status: status)
        }
    }
}
