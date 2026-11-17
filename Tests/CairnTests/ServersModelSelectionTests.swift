import XCTest
import CairnChatDomain
import CairnAppUI
import CairnPersistence

/// One tap on the Servers screen decides what answers the next turn, and the chat restores the model
/// that server was last used with. These run the real view model against a real SwiftData-backed
/// choice, because the claim being tested is both halves of P1 at once: the switch is instant, and
/// it is durable. The doubles come from `ServersTestDoubles.swift`.
@MainActor
final class ServersModelSelectionTests: XCTestCase {

    private func server(_ name: String, port: Int) -> ServerProfile {
        ServerProfile(name: name, kind: .ollama, baseURLString: "http://192.168.1.20:\(port)")
    }

    private func makeModel() throws -> (ServersModel, SwiftDataStore, ServerSelectionModel) {
        let store = try SwiftDataStore(inMemory: true)
        let selection = ServerSelectionModel(storing: store)
        let model = ServersModel(
            storing: store,
            testing: StubTester(),
            managing: StubModelService(),
            secrets: MemorySecretStore(),
            selection: selection
        )
        return (model, store, selection)
    }

    private func saved(_ model: ServersModel, named name: String) throws -> ServerProfile {
        try XCTUnwrap(model.profiles.first { $0.name == name })
    }

    func testTappingUsePointsTheChatAtThatServerAndTellsTheWorkspace() throws {
        let (model, _, selection) = try makeModel()
        XCTAssertTrue(model.save(server("Box", port: 11434), token: nil))
        let box = try saved(model, named: "Box")

        var handedOver: ServerProfile?
        model.onActiveServerChange = { handedOver = $0 }
        model.use(box)

        XCTAssertEqual(selection.activeProfileID, box.id)
        XCTAssertEqual(handedOver?.id, box.id, "the chat is handed the server in the same tap")
        XCTAssertTrue(model.isInUse(box))
    }

    /// A switch made in the chat is true on the Servers screen at once — one shared choice, read
    /// live rather than copied.
    func testAChoiceMadeInTheChatIsTrueOnTheServersScreenAtOnce() throws {
        let (model, _, selection) = try makeModel()
        XCTAssertTrue(model.save(server("Box", port: 11434), token: nil))
        let box = try saved(model, named: "Box")

        selection.setActive(box.id)

        XCTAssertTrue(model.isInUse(box), "the row shows the dot without waiting for a reload")
        XCTAssertEqual(model.activeProfile()?.id, box.id)
    }

    func testASwitchedOffServerIsRefusedOutLoud() throws {
        let (model, _, selection) = try makeModel()
        var off = server("Sleeping box", port: 11434)
        off.enabled = false
        XCTAssertTrue(model.save(off, token: nil))
        let stored = try saved(model, named: "Sleeping box")

        var handedOver: ServerProfile?
        model.onActiveServerChange = { handedOver = $0 }
        model.use(stored)

        XCTAssertNil(selection.activeProfileID, "a server that cannot answer is not made active anyway")
        XCTAssertNil(model.activeProfile(), "and the chat is not left pointing at it")
        XCTAssertNil(handedOver, "nothing is handed to the workspace")
        XCTAssertTrue(model.notice?.contains("Turn on") ?? false, "the refusal says what to do")
    }

    func testAPublicServerWithoutTheOptInIsRefusedAndTheNoticeNamesTheTrade() throws {
        let (model, _, selection) = try makeModel()
        let cloud = ServerProfile(
            name: "Hosted", kind: .openAICompatible, baseURLString: "https://api.some-provider.example"
        )
        XCTAssertTrue(model.save(cloud, token: nil), "a public profile saves while it stays shut to traffic")

        model.use(try saved(model, named: "Hosted"))

        XCTAssertNil(selection.activeProfileID)
        XCTAssertTrue(
            model.notice?.contains("leave this device") ?? false,
            "the notice has to name the outbound opt-in, not just say no"
        )
    }

    func testSwitchingBackRestoresTheModelThatServerWasLastUsedWith() throws {
        let (model, _, selection) = try makeModel()
        XCTAssertTrue(model.save(server("Studio", port: 1234), token: nil))
        XCTAssertTrue(model.save(server("Box", port: 11434), token: nil))
        let studio = try saved(model, named: "Studio")
        let box = try saved(model, named: "Box")

        model.use(box)
        selection.remember(modelID: "qwen3:8b", forProfile: box.id)
        XCTAssertNil(model.lastModel(for: studio), "a server never used has no remembered model")

        model.use(studio)
        model.use(box)

        XCTAssertEqual(selection.activeProfileID, box.id)
        XCTAssertEqual(model.lastModel(for: box), "qwen3:8b", "the row names what the next turn will use")
    }

    func testDeletingTheActiveServerRepointsTheChatAtAnotherOne() throws {
        let (model, _, selection) = try makeModel()
        XCTAssertTrue(model.save(server("Studio", port: 1234), token: nil))
        XCTAssertTrue(model.save(server("Box", port: 11434), token: nil))
        let studio = try saved(model, named: "Studio")
        model.use(studio)
        selection.remember(modelID: "qwen3-32b", forProfile: studio.id)

        var handedOver: ServerProfile?
        model.onActiveServerChange = { handedOver = $0 }
        model.delete(studio)

        let box = try saved(model, named: "Box")
        XCTAssertNotEqual(selection.activeProfileID, studio.id, "the chat cannot stay pointed at a deleted server")
        XCTAssertEqual(model.activeProfile()?.id, box.id, "it falls back to a server that can answer")
        XCTAssertEqual(handedOver?.id, box.id, "and the workspace is told rather than left on a dead engine")
        XCTAssertNil(model.lastModel(for: studio), "a deleted server leaves no remembered model behind")
    }

    /// The cloud kind arrives named, prefilled, and switched off; a LAN kind arrives empty, because
    /// nobody should guess the user's address for them.
    func testANewServerArrivesAsTheDraftItsKindWants() throws {
        let (model, _, _) = try makeModel()

        let cloud = model.draft(for: .ollamaCloud)
        XCTAssertFalse(cloud.name.isEmpty, "the cloud server knows its own name")
        XCTAssertEqual(cloud.baseURLString, "https://\(ServerBackend.cloudHost)")
        XCTAssertFalse(cloud.enabled, "and it is off until the user says otherwise")
        XCTAssertFalse(cloud.publicInternetOptIn, "an opt-in is never prefilled")

        let lan = model.draft(for: .ollama)
        XCTAssertEqual(lan.baseURLString, "http://", "only the scheme is prefilled; the user's address is never guessed")
        XCTAssertTrue(lan.name.isEmpty, "and nobody names the box for them")
    }
}

