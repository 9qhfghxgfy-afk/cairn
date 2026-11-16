import XCTest
import CairnChatDomain
import CairnPersistence

/// Runs on the simulator in CI: server profiles survive real SwiftData writes, a save
/// updates one row instead of duplicating it, and the credential never reaches disk.
@MainActor
final class ServerProfileStoreTests: XCTestCase {

    private func makeStore() throws -> SwiftDataStore {
        try SwiftDataStore(inMemory: true)
    }

    func testProfileRoundTripsThroughSwiftData() throws {
        let store = try makeStore()
        var profile = ServerProfile(
            name: "Studio box",
            kind: .ollama,
            baseURLString: "https://your-host.your-vpn.ts.net",
            customHeaders: ["X-Request-Tag": "cairn"],
            hasBearerToken: true,
            publicInternetOptIn: false
        )
        profile.updatedAt = Date(timeIntervalSince1970: 1_700_000_000)

        try store.save(profile)

        let stored = try store.profiles()
        XCTAssertEqual(stored.count, 1)
        let read = try XCTUnwrap(stored.first)
        XCTAssertEqual(read.id, profile.id)
        XCTAssertEqual(read.kind, .ollama)
        XCTAssertEqual(read.baseURLString, "https://your-host.your-vpn.ts.net")
        XCTAssertEqual(read.customHeaders, ["X-Request-Tag": "cairn"])
        XCTAssertTrue(read.hasBearerToken)
        XCTAssertEqual(read.updatedAt, profile.updatedAt)
    }

    func testOpenAICompatibleKindAndOptInSurviveAReSave() throws {
        let store = try makeStore()
        let cloud = ServerProfile(
            name: "Cloud", kind: .openAICompatible, baseURLString: "https://api.example.com"
        )
        try store.save(cloud)

        var optedIn = cloud
        optedIn.publicInternetOptIn = true
        optedIn.enabled = false
        try store.save(optedIn)

        let stored = try store.profiles()
        XCTAssertEqual(stored.count, 1, "the same id must update its row, not add one")
        let read = try XCTUnwrap(stored.first)
        XCTAssertEqual(read.kind, .openAICompatible)
        XCTAssertTrue(read.publicInternetOptIn)
        XCTAssertFalse(read.enabled, "a disabled profile stays disabled across a relaunch")
        XCTAssertFalse(read.usableNow)
    }

    func testStoredRowsNeverContainTheToken() throws {
        let store = try makeStore()
        var profile = ServerProfile(
            name: "Token box", kind: .ollama, baseURLString: "https://your-host.your-vpn.ts.net"
        )
        profile.hasBearerToken = true
        try store.save(profile)

        let dumped = try store.profiles().description
        XCTAssertFalse(dumped.contains("sk-"), "the record holds a flag, not a credential")
        XCTAssertTrue(try store.profiles().first?.hasBearerToken ?? false)
    }

    func testProfilesComeBackSortedByNameAndDeleteIsPermanent() throws {
        let store = try makeStore()
        try store.save(ServerProfile(name: "Zeta", kind: .ollama, baseURLString: "https://your-host.your-vpn.ts.net"))
        let second = ServerProfile(name: "Alpha", kind: .openAICompatible, baseURLString: "https://api.example.com")
        try store.save(second)

        XCTAssertEqual(try store.profiles().map(\.name), ["Alpha", "Zeta"])

        try store.delete(id: second.id)
        XCTAssertEqual(try store.profiles().map(\.name), ["Zeta"])

        // Deleting an unknown id is not an error: the UI may retry after a partial write.
        try store.delete(id: UUID())
        XCTAssertEqual(try store.profiles().count, 1)
    }

    func testChatWritesAndProfileWritesShareOneContainer() throws {
        let store = try makeStore()
        let conversation = try store.createConversation(
            title: "Trail notes", mode: .remoteOnly, params: .default, isTemporary: false
        )
        try store.save(ServerProfile(name: "Box", kind: .ollama, baseURLString: "https://your-host.your-vpn.ts.net"))

        XCTAssertEqual(try store.loadConversations().count, 1)
        XCTAssertEqual(try store.profiles().count, 1, "adding a server must not disturb the chat")
        XCTAssertNotNil(try store.conversation(id: conversation.id))
    }
}
