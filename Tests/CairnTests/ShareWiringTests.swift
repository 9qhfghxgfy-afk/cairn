import CairnAppUI
import CairnChatDomain
import CairnPersistence
import CairnProviderRemote
import SwiftUI
import XCTest

/// P4's UI and app half: what the switch does, what the screen shows, and the scene rule that keeps the
/// port foreground-only.
///
/// Nothing here renders a view or touches `UIPasteboard`, and no test binds a port — the socket half is
/// proven on the macOS host lane against a real loopback listener. What is proven here is the part that
/// only a simulator build can prove: the app-layer wiring that puts a live engine registry, a real
/// Keychain-backed vault and a surface behind one screen, and the rules the screen applies to them.
@MainActor
final class ShareWiringTests: XCTestCase {

    private let entry = ShareModelEntry(id: "cairn-mock", displayName: "Cairn Mock", engineID: "cairn-mock")

    private func surface(
        _ decision: ShareStartDecision = .allowed,
        refusal: ShareRefusal = .needsToken
    ) -> FakeShareSurface {
        let fake = FakeShareSurface()
        fake.decision = decision
        fake.refusal = refusal
        fake.catalog = [entry]
        return fake
    }

    private func shareModel(on fake: FakeShareSurface, vault: FakeTokenVault = FakeTokenVault()) -> ShareModel {
        ShareModel(serving: fake, listing: fake, tokens: vault)
    }

    /// Turning the switch on opens the port the user set, with the engines they ticked, under a key the
    /// vault actually generated. All three at once matter: a port on the wrong number, an engine nobody
    /// ticked, or a key nobody generated is each a different bug the user cannot see.
    func testTheSwitchOpensThePortTheKeyAndTheTickedEnginesTogether() async {
        let fake = surface()
        let share = shareModel(on: fake)
        share.refresh()
        share.settings.sharedEngineIDs = ["cairn-mock"]

        await share.setSharing(true)

        XCTAssertEqual(fake.starts.count, 1)
        XCTAssertEqual(fake.starts[0].port, ShareSettings.defaultPort)
        XCTAssertEqual(fake.starts[0].engineIDs, ["cairn-mock"])
        XCTAssertTrue(SharePolicy.tokenIsUsable(fake.starts[0].token), "a port never opens on a key nobody made")
        XCTAssertTrue(share.isEnabled)
        XCTAssertEqual(share.status.state, .running)
        XCTAssertEqual(share.statusLine, ShareStatusText.statusLine(share.status))
    }

    /// A refusal keeps the switch off and says which rule stopped it. A switch that snapped back with
    /// nothing on screen is the failure mode this whole screen exists to avoid.
    func testARefusalKeepsTheSwitchOffAndNamesTheRuleThatStoppedIt() async {
        let fake = surface(.refused(.noAddress), refusal: .noAddress)
        let share = shareModel(on: fake)
        share.refresh()
        share.settings.sharedEngineIDs = ["cairn-mock"]

        await share.setSharing(true)

        XCTAssertFalse(share.isEnabled)
        XCTAssertEqual(share.status.state, .failed)
        XCTAssertEqual(share.notice, ShareStatusText.failureText(.noAddress))
    }

    /// The key is generated, not typed, and the screen shows only its ends. The full key is still what
    /// Copy hands over — a laptop cannot be configured from a masked string — but a shoulder or a
    /// screenshot does not get it.
    func testTheKeyComesFromTheVaultAndTheScreenShowsOnlyItsEnds() async {
        let vault = FakeTokenVault()
        let share = shareModel(on: surface(), vault: vault)
        share.refresh()
        XCTAssertTrue(share.token.isEmpty, "asking what the key is must not create one")
        share.settings.sharedEngineIDs = ["cairn-mock"]

        await share.setSharing(true)

        XCTAssertEqual(vault.rotations, 1, "an empty vault is filled by rotation, not by a typed word")
        XCTAssertEqual(share.token, vault.draws[0])
        XCTAssertEqual(share.maskedToken, "firs" + String(repeating: "•", count: 10) + "pass")
        XCTAssertFalse(share.maskedToken.contains(share.token))
    }

    /// Rotation is the revocation button: the old key stops working, and the screen says so in the same
    /// breath, because "regenerate" without "your other machines break now" is a surprise.
    func testRegeneratingReplacesTheKeyAndWarnsThatOldClientsMustBeReset() async {
        let vault = FakeTokenVault()
        let share = shareModel(on: surface(), vault: vault)
        share.refresh()
        share.settings.sharedEngineIDs = ["cairn-mock"]
        await share.setSharing(true)

        share.regenerateToken()

        XCTAssertEqual(vault.rotations, 2)
        XCTAssertEqual(share.token, vault.draws[1])
        XCTAssertTrue((share.notice ?? "").contains("old one"))
        XCTAssertTrue(vault.writes.contains(vault.draws[1]), "the new key is in the vault, not just on screen")
    }

    /// The served set is agreed at the moment the port opens, so the picker and the port go grey while it
    /// is open rather than accept a change a client would never see. Turning sharing off reopens them.
    func testTheServedSetCannotMoveWhileThePortIsOpen() async {
        let fake = surface()
        let share = shareModel(on: fake)
        share.refresh()
        XCTAssertTrue(share.canEditSelection)
        share.settings.sharedEngineIDs = ["cairn-mock"]
        await share.setSharing(true)

        XCTAssertFalse(share.canEditSelection)
        share.toggleEngine(id: "cairn-mock")
        share.setPort(9999)
        XCTAssertEqual(share.settings.sharedEngineIDs, ["cairn-mock"], "a tick while running changes nothing")
        XCTAssertEqual(share.settings.port, ShareSettings.defaultPort)

        await share.setSharing(false)
        XCTAssertEqual(fake.stopCount, 1)
        XCTAssertTrue(share.canEditSelection)
        share.toggleEngine(id: "another-engine")
        XCTAssertEqual(share.settings.sharedEngineIDs, ["cairn-mock", "another-engine"])
    }

    /// An engine that stops existing stops being offered: deleting the profile it came from must empty the
    /// row rather than leave a name a client could ask for and never get.
    func testAnEngineThatStoppedExistingStopsBeingOffered() async {
        let fake = surface()
        let share = shareModel(on: fake)
        share.refresh()
        share.settings.sharedEngineIDs = ["cairn-mock"]
        fake.catalog = []

        share.refresh()

        XCTAssertTrue(share.offered.isEmpty)
        XCTAssertTrue(share.settings.sharedEngineIDs.isEmpty, "a ticked engine that vanished is dropped, not kept")
    }

    /// The foreground rule, stated as a function so it can be tested with no scene: a port is allowed only
    /// while the person using the phone can see that it is open.
    func testAPortIsAllowedOnlyWhileTheAppIsOnScreen() {
        XCTAssertTrue(ShareWiring.allowsListening(.active))
        XCTAssertFalse(ShareWiring.allowsListening(.inactive))
        XCTAssertFalse(ShareWiring.allowsListening(.background))
    }

    /// Leaving the foreground closes the port and turns the switch off, and says why. A switch left glowing
    /// over a port iOS already took away would teach the user that nothing on this screen can be trusted.
    func testLeavingTheForegroundClosesThePortAndTurnsTheSwitchOff() async {
        let share = shareModel(on: surface())
        share.refresh()
        share.settings.sharedEngineIDs = ["cairn-mock"]
        await share.setSharing(true)

        await share.releaseToBackground()

        XCTAssertEqual(share.status.state, .off)
        XCTAssertFalse(share.isEnabled)
        XCTAssertEqual(share.notice, ShareStatusText.backgroundNote)

        // Nothing running, nothing to close: a phase change must not manufacture a stop.
        let idle = shareModel(on: surface())
        idle.refresh()
        await idle.releaseToBackground()
        XCTAssertNil(idle.notice)
    }

    /// The app-layer install: the Servers screen gets its share row over the **live** engine list, and
    /// installing opens nothing — no port, no key. The surface is what the user switches on, later.
    func testInstallingPutsTheRowOnTheServersScreenOverTheLiveRegistryAndOpensNothing() async throws {
        let store = try SwiftDataStore(inMemory: true)
        let servers = ServersModel(
            storing: store, testing: StubTester(), managing: StubModelService(),
            secrets: MemorySecretStore(), selection: ServerSelectionModel(storing: store)
        )
        let registry = ProviderRegistry(providers: [
            MockStreamingProvider(id: "cairn-mock"),
            MockStreamingProvider(id: "cairn-second"),
        ])
        let vault = ShareTokenHolding(service: "app.cairn.share-key.test", operation: MemoryKeychain())

        let wiring = ShareWiring.install(on: servers, registry: registry, tokens: vault)
        let share = try XCTUnwrap(servers.share)
        share.refresh()

        XCTAssertEqual(share.offered.map(\.id), ["cairn-mock", "cairn-second"])
        XCTAssertEqual(share.status.state, .off, "installing a surface must not open a port")
        XCTAssertNil(vault.token(), "installing a surface must not create a key")

        // The handoff the milestone asks for: whatever this process can actually run becomes the served
        // table, filtered to what was ticked, with no ghost names for engines that are not there.
        let table = ShareWiring.servedTable(from: registry, selected: ["cairn-second", "no-such-engine"])
        XCTAssertEqual(table.servedIDs, ["cairn-second"])

        // And the phase hook runs through the real surface, which never bound anything in this test.
        await wiring.handlePhase(.background)
        XCTAssertFalse(share.isEnabled)
        XCTAssertEqual(share.status.state, .off)
    }

    /// The wall between the two directions of credential, on the real store code with a fake Keychain
    /// behind it: the inbound key that opens this phone and the tokens this phone presents to other
    /// machines live in different Keychain services, and neither can read the other.
    func testTheShareKeyVaultIsNotTheOutboundTokenVault() throws {
        XCTAssertNotEqual(ShareTokenHolding.shareService, KeychainSecretStore.defaultService)
        let shared = MemoryKeychain()
        let shareVault = ShareTokenHolding(operation: shared)
        let profileID = UUID()

        let key = shareVault.rotate()
        XCTAssertFalse(key.isEmpty)
        let outbound = KeychainSecretStore(operation: shared)
        XCTAssertNil(outbound.secret(for: profileID), "the share key is not readable as a server token")

        try outbound.setSecret("sk-outbound", for: profileID)
        XCTAssertEqual(shareVault.token(), key, "a server token never becomes the key that opens this phone")
        XCTAssertEqual(outbound.secret(for: profileID), "sk-outbound")
        XCTAssertTrue(shared.storedQueries.contains { $0.service == ShareTokenHolding.shareService })
    }
}
