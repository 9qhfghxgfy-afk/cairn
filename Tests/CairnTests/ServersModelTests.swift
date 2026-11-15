import XCTest
import CairnChatDomain
import CairnAppUI
import CairnProviderRemote

/// The Servers screen's rules, tested through its view model: validation refuses credentials
/// and plaintext, the token only ever reaches the secret store, and the engine list follows
/// the saved profiles through the real provider factory.
@MainActor
final class ServersModelTests: XCTestCase {

    private func makeModel(
        _ store: RecordingProfileStore = RecordingProfileStore(),
        secrets: MemorySecretStore = MemorySecretStore(),
        registry: ProviderRegistry? = nil
    ) -> (ServersModel, RecordingProfileStore, MemorySecretStore) {
        let factory = RemoteProviderFactory(secrets: secrets)
        let model = ServersModel(
            storing: store,
            testing: StubTester(),
            managing: StubModelService(),
            secrets: secrets,
            registry: registry,
            // Same wiring as the app: the mock is a base engine, so publishing remote
            // engines replaces the list as base + saved servers, never the mock alone.
            baseEngines: [MockStreamingProvider()],
            engineBuilder: { profiles in factory.providers(from: profiles) }
        )
        return (model, store, secrets)
    }

    /// A fresh profile each time it is read, so a test must hold one value and reuse it.
    private var tailnet: ServerProfile {
        ServerProfile(name: "Studio box", kind: .ollama, baseURLString: "https://your-host.your-tailnet.ts.net")
    }

    func testCredentialHeaderIsRefusedBeforeAnythingIsStored() {
        let (model, store, _) = makeModel()
        var profile = tailnet
        profile.customHeaders = ["Authorization": "Bearer pasted-by-mistake"]

        XCTAssertFalse(model.save(profile, token: nil))
        XCTAssertTrue(store.saved.isEmpty, "a refused save must not write a row")
        XCTAssertTrue(model.notice?.contains("Keychain") ?? false, "the notice must say where the token belongs")
    }

    func testPlaintextOffLoopbackIsRefused() {
        let (model, store, _) = makeModel()
        let lanBox = ServerProfile(name: "Wired box", kind: .ollama, baseURLString: "http://10.0.0.5:11434")

        XCTAssertFalse(model.save(lanBox, token: nil))
        XCTAssertTrue(store.saved.isEmpty)
        XCTAssertTrue(model.notice?.contains("tailscale serve") ?? false, "the notice must teach the fix")
    }

    func testURLIsCanonicalizedAndTheTokenReachesOnlyTheSecretStore() throws {
        let (model, store, secrets) = makeModel()
        var profile = tailnet
        profile.name = "  Studio box  "
        profile.baseURLString = "https://your-host.your-tailnet.ts.net/"

        XCTAssertTrue(model.save(profile, token: "sk-secret"))
        let stored = try XCTUnwrap(store.saved[profile.id])
        XCTAssertEqual(stored.name, "Studio box")
        XCTAssertEqual(stored.baseURLString, "https://your-host.your-tailnet.ts.net")
        XCTAssertTrue(stored.hasBearerToken)
        XCTAssertEqual(secrets.items[profile.id], "sk-secret")
        XCTAssertFalse(store.saved.description.contains("sk-"), "the settings store never sees the token")
    }

    func testRemovingTheTokenClearsBothTheSecretAndTheFlag() throws {
        let (model, store, secrets) = makeModel()
        let profile = tailnet
        XCTAssertTrue(model.save(profile, token: "sk-secret"))
        let stored = try XCTUnwrap(store.saved[profile.id])
        XCTAssertTrue(model.hasToken(stored))

        model.removeToken(stored)

        XCTAssertNil(secrets.items[profile.id])
        XCTAssertFalse(try XCTUnwrap(store.saved[profile.id]).hasBearerToken)
        XCTAssertFalse(model.hasToken(stored))
    }

    func testDeletingAProfileDeletesItsTokenToo() throws {
        let (model, store, secrets) = makeModel()
        let profile = tailnet
        XCTAssertTrue(model.save(profile, token: "sk-secret"))
        let stored = try XCTUnwrap(store.saved[profile.id])

        model.delete(stored)

        XCTAssertTrue(store.saved.isEmpty)
        XCTAssertEqual(store.deleted, [profile.id])
        XCTAssertTrue(secrets.items.isEmpty, "an orphaned Keychain item is a credential with nothing to point at")
    }

    func testDisabledServerLeavesTheEngineList() throws {
        let registry = ProviderRegistry(providers: [MockStreamingProvider()])
        let (model, store, _) = makeModel(registry: registry)
        let profile = tailnet
        XCTAssertTrue(model.save(profile, token: nil))

        XCTAssertEqual(registry.providers.count, 2, "the mock plus the saved server")

        let stored = try XCTUnwrap(store.saved[profile.id])
        model.setEnabled(stored, false)
        XCTAssertEqual(registry.providers.count, 1, "a disabled server cannot answer a turn")
        XCTAssertFalse(try XCTUnwrap(store.saved[profile.id]).enabled)

        model.setEnabled(try XCTUnwrap(store.saved[profile.id]), true)
        XCTAssertEqual(registry.providers.count, 2)
    }

    func testTestAndRefreshUpdateTheRowWithoutLeavingItBusy() async throws {
        let (model, _, _) = makeModel()
        let profile = tailnet
        XCTAssertTrue(model.save(profile, token: nil))
        let stored = try XCTUnwrap(model.profiles.first)

        await model.test(stored)
        XCTAssertEqual(model.outcomes[profile.id], StubTester().outcome)
        XCTAssertFalse(model.isBusy(stored))

        await model.refreshModels(stored)
        XCTAssertEqual(model.modelCounts[profile.id], 1)
        XCTAssertFalse(model.isBusy(stored))
    }

    func testUnreadableStoreSurfacesANoticeInsteadOfCrashing() {
        let store = RecordingProfileStore()
        store.failure = RemoteError.httpStatus(401, serverMessage: nil)
        let model = ServersModel(
            storing: store,
            testing: StubTester(),
            managing: StubModelService(),
            secrets: MemorySecretStore(),
            engineBuilder: { _ in [] }
        )
        XCTAssertTrue(model.profiles.isEmpty)
        XCTAssertNotNil(model.notice)
    }
}
