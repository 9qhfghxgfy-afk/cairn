import XCTest
import CairnChatDomain
import CairnAppUI
import CairnProviderRemote
import CairnPersistence

/// A Keychain the test can seed, so the route decision can be pinned without a secure enclave.
@MainActor
final class MemoryKeychain: KeychainOperating, @unchecked Sendable {
    private var items: [KeychainQuery: Data] = [:]

    func set(_ query: KeychainQuery, value: Data) throws { items[query] = value }
    func data(for query: KeychainQuery) throws -> Data? { items[query] }
    func remove(_ query: KeychainQuery) throws { items[query] = nil }
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
        let armed = registry(acknowledged)
        for name in BuiltInTool.webNames {
            XCTAssertNotNil(armed.tool(name), "\(name) arrives with the acknowledgement")
        }
        XCTAssertEqual(armed.availableDefinitions(context: offered).count, BuiltInTool.allNames.count)

        // A device with no composer gets no mail tool rather than a tool that answers "done" and opens
        // nothing.
        let noComposer = BuiltInToolRegistry.make(searchState: { .default }, webToolsAllowed: false)
        XCTAssertEqual(noComposer.names, [BuiltInTool.calculator], "only what this build can really do")
    }

    /// The key that unlocks the cloud route is read from the Keychain for the server this chat is on,
    /// and only for a server of the cloud kind. A LAN profile's bearer token is that server's own API
    /// credential; letting it decide a search route would send it onward to a third party.
    func testTheCloudKeyIsReadOnlyForAServerOfTheCloudKind() throws {
        let store = try SwiftDataStore(inMemory: true)
        let servers = ServersModel(
            storing: store, testing: StubTester(), managing: StubModelService(),
            secrets: MemorySecretStore(), selection: ServerSelectionModel(storing: store)
        )
        let cloud = ServerProfile(
            name: "Cloud", kind: .ollamaCloud, baseURLString: "https://ollama.com",
            hasBearerToken: true, enabled: true, publicInternetOptIn: true
        )
        XCTAssertTrue(servers.save(cloud, token: nil))
        let saved = try XCTUnwrap(servers.profiles.first { $0.name == "Cloud" })
        servers.use(saved)

        let secrets = KeychainSecretStore(service: "app.cairn.test", operation: MemoryKeychain())
        let wired = ToolWiring(settings: ThemeModel(settings: acknowledged), secrets: secrets, servers: servers)

        XCTAssertFalse(wired.searchState().routing.hasOllamaCloudKey, "no key stored yet")
        XCTAssertEqual(wired.searchState().route, .keyless, "a cloud profile with no key falls through")

        try secrets.setSecret("cloud-key", for: saved.id)
        let armed = wired.searchState()
        XCTAssertEqual(armed.route, .ollamaCloud, "the server in use, with its own key, goes first")
        XCTAssertEqual(armed.cloudToken, "cloud-key")

        let box = ServerProfile(
            name: "Box", kind: .ollama, baseURLString: "http://192.168.1.20:11434", hasBearerToken: true
        )
        XCTAssertTrue(servers.save(box, token: nil))
        let lan = try XCTUnwrap(servers.profiles.first { $0.name == "Box" })
        try secrets.setSecret("lan-token", for: lan.id)
        servers.use(lan)
        let onLAN = wired.searchState()
        XCTAssertNil(onLAN.cloudToken, "a LAN server's token never becomes a search key")
        XCTAssertFalse(onLAN.routing.hasOllamaCloudKey)
        XCTAssertEqual(onLAN.route, .keyless)
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
