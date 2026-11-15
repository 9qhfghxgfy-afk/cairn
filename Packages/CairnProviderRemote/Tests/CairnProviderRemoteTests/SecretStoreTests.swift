import Foundation
import XCTest
import CairnChatDomain
@testable import CairnProviderRemote

/// The token lives in the Keychain and nowhere else. These tests use a fake operator, so the
/// policy is verified on any host: the profile uuidString is the only key material, an empty
/// token deletes, and one profile can never read another one's secret.
@MainActor
final class SecretStoreTests: XCTestCase {

    func testTokenRoundTripsThroughTheKeychainOnly() throws {
        let fake = FakeKeychainOperator()
        let store = KeychainSecretStore(operation: fake)
        let profileID = UUID()

        try store.setSecret("sk-secret", for: profileID)

        XCTAssertEqual(store.secret(for: profileID), "sk-secret")
        XCTAssertEqual(
            fake.storedQueries,
            [KeychainQuery(service: KeychainSecretStore.defaultService, account: profileID.uuidString)]
        )
    }

    func testEmptyTokenDeletesRatherThanStoringAnEmptyValue() throws {
        let fake = FakeKeychainOperator()
        let store = KeychainSecretStore(operation: fake)
        let profileID = UUID()

        try store.setSecret("sk-secret", for: profileID)
        try store.setSecret("", for: profileID)

        XCTAssertNil(store.secret(for: profileID))
        XCTAssertTrue(fake.storedQueries.isEmpty, "clearing the field must clear the Keychain item")
    }

    func testProfilesCannotReadEachOthersSecret() throws {
        let store = KeychainSecretStore(operation: FakeKeychainOperator())
        let first = UUID()
        let second = UUID()

        try store.setSecret("sk-first", for: first)

        XCTAssertEqual(store.secret(for: first), "sk-first")
        XCTAssertNil(store.secret(for: second))

        try store.removeSecret(for: first)
        try store.setSecret("sk-second", for: second)
        XCTAssertEqual(store.secret(for: second), "sk-second")
        XCTAssertNil(store.secret(for: first), "deleting a profile must not leave a readable token")
    }

    func testKeychainFailureIsReportedAsAStatusNotAsItemContents() {
        let failure = KeychainFailure(operation: "copy", status: -25300)
        let text = String(describing: failure)
        XCTAssertTrue(text.contains("copy"))
        XCTAssertTrue(text.contains("-25300"))
        XCTAssertFalse(text.contains("sk-"), "a Keychain error must not echo the value it failed on")
    }
}
