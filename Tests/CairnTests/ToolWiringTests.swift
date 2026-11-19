import Foundation
import XCTest
import CairnChatDomain
import CairnAppUI
import CairnProviderRemote
import CairnPersistence

/// A Keychain the test can seed, so the route decision can be pinned without a secure enclave. Not
/// main-actor-isolated: `KeychainOperating` is a nonisolated protocol, so the lock is what serialises
/// it — the same shape `FakeKeychainOperator` uses in the remote suite.
final class MemoryKeychain: KeychainOperating, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [KeychainQuery: Data] = [:]

    func set(_ query: KeychainQuery, value: Data) throws {
        lock.lock(); defer { lock.unlock() }
        items[query] = value
    }

    func data(for query: KeychainQuery) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return items[query]
    }

    func remove(_ query: KeychainQuery) throws {
        lock.lock(); defer { lock.unlock() }
        items[query] = nil
    }
}

/// P3b wiring: the app layer is the only place a registry can be built, because the tools it holds need
/// a window, a Keychain, and the two Settings switches. These tests run the real factory against real
/// stores — no double standing in for the switch that decides whether a web tool exists at all.
@MainActor
final class ToolWiringTests: XCTestCase {

    private var acknowledged: AppSettings {
        var settings = AppSettings.default
        settings.setOutboundWebAllowed(true)
        return settings
    }

    private func wiring(_ settings: AppSettings, servers: ServersModel? = nil) -> ToolWiring {
        ToolWiring(
            settings: ThemeModel(settings: settings),
            secrets: KeychainSecretStore(service: "app.cairn.test", operation: MemoryKeychain()),
            servers: servers
        )
    }

    private func registry(_ settings: AppSettings) -> ToolRegistry {
        wiring(settings).registry()
    }

    private let offered = ToolExecutionContext(toolsEnabled: true, outboundWebAllowed: true)

    /// The acknowledgement is what makes a web tool exist, not merely runnable: with it down, the three
    /// web tools are absent from the registry, so they are never advertised and never called. The
    /// on-device half keeps working, because arithmetic and a mail draft need no acknowledgement.
    func testTheAcknowledgementDecidesWhetherAWebToolExistsAtAll() {
        let unacknowledged = registry(.default)
        XCTAssertFalse(unacknowledged.isEmpty, "a chat with no web tools still has a calculator")
        XCTAssertTrue(unacknowledged.names.contains(BuiltInTool.calculator))
        XCTAssertTrue(unacknowledged.names.contains(BuiltInTool.composeMail))
        for name in BuiltInTool.webNames {
            XCTAssertNil(unacknowledged.tool(name), "\(name) is not in the registry at all")
        }
        XCTAssertTrue(unacknowledged.availableDefinitions(context: offered).allSatisfy { !$0.requiresPublicInternet })

        let armed = registry(acknowledged)
        for name in BuiltInTool.webNames {
            XCTAssertNotNil(armed.tool(name), "\(name) arrives with the acknowledgement")
        }
        // The registry assembled here has no position source, so `get_location` is deliberately absent — a
        // built-in that could only ever answer "no position" is not offered. Everything else this build can
        // really do is advertised once the acknowledgement is up. Compared by name rather than by count so the
        // assertion says which tool it is talking about when it breaks.
        XCTAssertEqual(
            armed.availableDefinitions(context: offered).map(\.name).sorted(),
            BuiltInTool.allNames.filter { $0 != BuiltInTool.getLocation }.sorted(),
            "the acknowledgement opens the web tools, and nothing else moved"
        )

        // A device with no composer gets no mail tool rather than a tool that answers "done" and opens
        // nothing.
        let noComposer = BuiltInToolRegistry.make(searchState: { WebSearchState() }, webToolsAllowed: false)
        XCTAssertEqual(noComposer.names, [BuiltInTool.calculator], "only what this build can really do")
    }

    /// The key a cloud search row uses is read from the Keychain for the one server profile that mirrors
    /// it, and only for a profile of the cloud kind. A LAN profile's bearer token is that server's own API
    /// credential; letting it decide a search row would send it onward to a third party.
    func testACloudRowTakesItsKeyOnlyFromTheProfileThatMirrorsIt() throws {
        let store = try SwiftDataStore(inMemory: true)
        let servers = ServersModel(
            storing: store, testing: StubTester(), managing: StubModelService(),
            secrets: MemorySecretStore(), selection: ServerSelectionModel(storing: store)
        )
        let theme = ThemeModel(settings: acknowledged)
        let secrets = KeychainSecretStore(service: "app.cairn.test", operation: MemoryKeychain())
        let wired = ToolWiring(settings: theme, secrets: secrets, servers: servers)

        let cloud = ServerProfile(
            name: "Cloud", kind: .ollamaCloud, baseURLString: "https://ollama.com",
            hasBearerToken: true, enabled: true, publicInternetOptIn: true
        )
        XCTAssertTrue(servers.save(cloud, token: nil))
        let saved = try XCTUnwrap(servers.profiles.first { $0.name == "Cloud" })
        servers.use(saved)

        // No key, no row. A search provider that cannot authenticate looks configured and then fails, which
        // is worse than never offering it.
        wired.syncCloudRows()
        XCTAssertFalse(
            wired.searchState().settings.allProviders.contains { $0.kind == .ollamaCloud },
            "a cloud profile without a key is not a provider"
        )

        try secrets.setSecret("cloud-key", for: saved.id)
        wired.syncCloudRows()
        let row = try XCTUnwrap(
            wired.searchState().settings.allProviders.first { $0.kind == .ollamaCloud }
        )
        XCTAssertEqual(row.credentialShape, .bearer, "the row says the shape its key travels in")

        // Selecting the row is what makes its own profile's key the secret a search carries.
        var chosen = wired.searchState().settings
        chosen.providers.select(id: row.id)
        theme.setWebSearch(chosen)
        XCTAssertEqual(wired.searchState().credential, "cloud-key", "the mirrored profile's key, no other")

        // A LAN server's API token belongs to that server. Neither switching to it nor syncing again may
        // put it on a search row — including a SearXNG row, which declares no credential at all.
        let box = ServerProfile(
            name: "Box", kind: .ollama, baseURLString: "http://192.168.1.20:11434", hasBearerToken: true
        )
        XCTAssertTrue(servers.save(box, token: nil))
        let lan = try XCTUnwrap(servers.profiles.first { $0.name == "Box" })
        try secrets.setSecret("lan-token", for: lan.id)
        servers.use(lan)
        wired.syncCloudRows()

        var withInstance = wired.searchState().settings
        let instance = WebSearchProviderProfile(
            kind: .searxng, displayName: "Box search", baseURLString: "http://192.168.1.20:8888"
        )
        try withInstance.providers.add(instance)
        theme.setWebSearch(withInstance)
        let onLAN = wired.searchState()
        XCTAssertEqual(onLAN.provider.kind, .searxng, "adding a row selects it")
        XCTAssertNil(onLAN.credential, "a row that declares no credential is handed nothing")
    }

    /// Installing reaches the workspace, the session live at that moment, and every session opened
    /// afterwards. A registry assembled before the acknowledgement would otherwise leave a chat armed
    /// for tools with a chip that offers arithmetic and nothing else — a switch that looks like it works.
    func testInstallingHandsTheWorkspaceAndEverySessionTheSameSurface() throws {
        let store = try SwiftDataStore(inMemory: true)
        let workspace = ChatWorkspace(
            persistentStore: store, providers: [MockStreamingProvider(id: "ollama")]
        )
        workspace.startNewChat()

        let wired = wiring(acknowledged)
        wired.install(on: workspace)
        XCTAssertEqual(workspace.toolRegistry.names, wired.registry().names)
        XCTAssertTrue(workspace.outboundWebAllowed)
        XCTAssertTrue(workspace.toolRegistry.names.contains(BuiltInTool.webSearch))
        let session = try XCTUnwrap(workspace.session)
        XCTAssertEqual(session.toolRegistry.names, workspace.toolRegistry.names)
        XCTAssertTrue(session.outboundWebAllowed)
        XCTAssertTrue(session.showsGenerationStats, "the statistics switch travels too")

        workspace.startNewChat()
        let fresh = try XCTUnwrap(workspace.session)
        XCTAssertEqual(fresh.toolRegistry.names, workspace.toolRegistry.names, "a chat opened later matches")

        // And the other way: a chat wired without the acknowledgement is offered no web tool at all.
        let plain = ChatWorkspace(persistentStore: store, providers: [MockStreamingProvider(id: "ollama")])
        plain.startNewChat()
        wiring(.default).install(on: plain)
        XCTAssertFalse(plain.outboundWebAllowed)
        XCTAssertTrue(plain.toolRegistry.names.contains(BuiltInTool.calculator))
        for name in BuiltInTool.webNames {
            XCTAssertNil(plain.toolRegistry.tool(name), "\(name) was never built")
        }
        let live = try XCTUnwrap(plain.session)
        XCTAssertEqual(live.toolRegistry.names, plain.toolRegistry.names, "the live session agrees")
        XCTAssertNil(live.toolRegistry.tool(BuiltInTool.webSearch), "and offers no web tool either")
    }
}
