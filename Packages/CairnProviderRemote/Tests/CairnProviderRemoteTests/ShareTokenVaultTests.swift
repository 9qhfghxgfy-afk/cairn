import Foundation
import XCTest
import CairnChatDomain
@testable import CairnProviderRemote

/// The inbound share key, and the wall between it and the outbound token vault.
///
/// These are the two claims P4 makes about the key: it is **generated** rather than typed, and it is
/// **not the same credential store** the app uses when it dials out. A shared Keychain namespace
/// between the two would mean rotating the key that opens this phone could reach a server token, and
/// that a server token could be read back as the key that opens this phone — so the namespace is
/// tested rather than commented.
@MainActor
final class ShareTokenVaultTests: XCTestCase {

    private func vault(_ operation: FakeKeychainOperator, generator: @escaping @Sendable () -> String = { ShareToken.generate() }) -> ShareTokenHolding {
        ShareTokenHolding(operation: operation, generator: generator)
    }

    func testAGeneratedKeyClearsThePolicyFloorAndLandsInTheShareNamespace() {
        let fake = FakeKeychainOperator()
        let key = vault(fake).rotate()

        XCTAssertTrue(SharePolicy.tokenIsUsable(key), "the shipped generator must clear the policy floor")
        XCTAssertEqual(
            fake.storedQueries,
            [KeychainQuery(service: ShareTokenHolding.shareService, account: ShareTokenHolding.shareTokenID.uuidString)]
        )
    }

    func testTheShareNamespaceIsNotTheOutboundTokenVault() {
        XCTAssertNotEqual(ShareTokenHolding.shareService, KeychainSecretStore.defaultService)

        // One Keychain, two vaults: a share key written through this holder is invisible to the
        // outbound store, and an outbound token is invisible as the share key.
        let shared = FakeKeychainOperator()
        let shareKey = vault(shared).rotate()
        let outbound = KeychainSecretStore(operation: shared)
        let profileID = UUID()

        XCTAssertNil(outbound.secret(for: profileID), "the share key must not be readable as a server token")
        try? outbound.setSecret("sk-outbound", for: profileID)
        XCTAssertEqual(vault(shared).token(), shareKey, "a server token must not become the share key")
    }

    func testRotateReplacesTheStoredKeySoAnOldClientStopsWorking() {
        let fake = FakeKeychainOperator()
        let holder = vault(fake)

        let first = holder.rotate()
        let second = holder.rotate()

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(holder.token(), second, "the surface must key on the newest rotation")
    }

    func testReadingTheKeyNeverWritesOne() {
        let fake = FakeKeychainOperator()

        XCTAssertNil(vault(fake).token())
        XCTAssertTrue(fake.storedQueries.isEmpty, "asking what the key is must not create a key")
    }

    func testClearRemovesTheItemRatherThanLeavingAReadableKey() {
        let fake = FakeKeychainOperator()
        let holder = vault(fake)
        holder.rotate()

        holder.clear()

        XCTAssertNil(holder.token())
        XCTAssertTrue(fake.storedQueries.isEmpty)
    }

    func testAWeakDrawIsRejectedUntilTheCandidateClearsTheFloor() {
        let fake = FakeKeychainOperator()
        let draws = DrawBox(["short", "also short", ShareToken.generate()])

        let key = vault(fake, generator: { draws.next() }).rotate()

        XCTAssertTrue(SharePolicy.tokenIsUsable(key))
        XCTAssertEqual(key, draws.values[2])
    }

    func testAKeyTheVaultRefusesToStoreIsNotHandedBackAsIfItWorked() {
        let holder = ShareTokenHolding(store: RefusingSecretStore())

        XCTAssertFalse(holder.save("a-key-long-enough-to-pass"))
        XCTAssertEqual(holder.rotate(), "", "a key the vault would not hold must not be shown to the user")
    }

    func testSavingAnEmptyKeyClearsTheItem() {
        let fake = FakeKeychainOperator()
        let holder = vault(fake)
        holder.rotate()

        XCTAssertTrue(holder.save(""))
        XCTAssertNil(holder.token())
    }
}

/// Draws a fixed list of generated keys, so the weak-draw loop is proven without a random generator.
private final class DrawBox: @unchecked Sendable {
    private let lock = NSLock()
    private var drawn = 0
    let values: [String]

    init(_ values: [String]) { self.values = values }

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        defer { drawn += 1 }
        return drawn < values.count ? values[drawn] : "short"
    }
}

/// A store whose Keychain write fails, which is the case the holder must not paper over. Isolated to
/// the main actor for the same reason the real vault is: `SecretStoring` is a main-actor protocol.
@MainActor
private struct RefusingSecretStore: SecretStoring {
    func setSecret(_ secret: String, for id: UUID) throws { throw KeychainFailure(operation: "add", status: -1) }
    func secret(for id: UUID) -> String? { nil }
    func removeSecret(for id: UUID) throws {}
}
