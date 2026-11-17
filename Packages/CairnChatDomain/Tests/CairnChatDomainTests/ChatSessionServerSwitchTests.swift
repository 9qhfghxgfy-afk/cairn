import XCTest
@testable import CairnChatDomain

/// One-tap server switching seen from the chat session, which is where a switch has to be true
/// immediately. Three things must happen together: the session repoints at that server's engine,
/// the shared `ServerSelectionModel` records it so the Servers screen agrees on the next read, and
/// the model that server was last used with comes back — while a model name is never carried to a
/// machine that does not have it.
@MainActor
final class ChatSessionServerSwitchTests: XCTestCase {

    /// Two servers on documented example LAN addresses, each with its own catalog.
    private let home = ServerProfile(
        name: "Home box", kind: .ollama, baseURLString: "http://192.168.1.20:11434"
    )
    private let studio = ServerProfile(
        name: "Studio box", kind: .lmStudio, baseURLString: "http://192.168.1.10:1234"
    )

    private func makeSession(
        _ selection: ServerSelectionModel?,
        homeModels: [String] = ["llama3.2:3b", "qwen3:8b"],
        studioModels: [String] = ["qwen3-32b"]
    ) -> ChatSessionModel {
        let engines: [any InferenceProvider] = [
            MockStreamingProvider(),
            ServerEngineStub(profile: home, modelIDs: homeModels),
            ServerEngineStub(profile: studio, modelIDs: studioModels),
        ]
        let conversation = Conversation(title: "New chat", mode: .remoteOnly, isTemporary: true)
        let session = ChatSessionModel(
            conversation: conversation,
            store: EphemeralStore(),
            registry: ProviderRegistry(providers: engines)
        )
        session.selection = selection
        return session
    }

    func testSwitchingRepointsTheEngineAndWritesTheSharedChoice() async throws {
        let store = RecordingSelectionStore()
        let selection = ServerSelectionModel(storing: store)
        let session = makeSession(selection)

        session.select(serverProfileID: home.id)
        await settle(session, models: 2)

        XCTAssertEqual(session.selectedProviderID, home.engineID)
        XCTAssertEqual(selection.activeProfileID, home.id)
        XCTAssertEqual(store.stored.activeProfileID, home.id, "a switch that evaporates on relaunch is not a switch")

        session.select(serverProfileID: studio.id)
        await settle(session, models: 1)

        XCTAssertEqual(session.selectedProviderID, studio.engineID)
        XCTAssertEqual(selection.activeProfileID, studio.id)
        XCTAssertEqual(store.stored.activeProfileID, studio.id)
        XCTAssertEqual(session.availableModels.map(\.id), ["qwen3-32b"], "the new server's catalog replaces the old")
    }

    func testEachServerRestoresItsOwnLastModel() async throws {
        let selection = ServerSelectionModel(storing: RecordingSelectionStore())
        let session = makeSession(selection)

        session.select(serverProfileID: home.id)
        await settle(session, models: 2)
        session.choose(model: "qwen3:8b")
        XCTAssertEqual(selection.lastModel(forProfile: home.id), "qwen3:8b")

        session.select(serverProfileID: studio.id)
        await settle(session, models: 1)
        XCTAssertEqual(session.selectedModelID, "qwen3-32b")
        XCTAssertNotEqual(selection.lastModel(forProfile: studio.id), "qwen3:8b")

        // Back to the first server: what it was last used with, not what the other one had.
        session.apply(serverProfileID: home.id)
        XCTAssertEqual(session.selectedModelID, "qwen3:8b", "restored before the catalog is even fetched")
        await settle(session, models: 2)
        XCTAssertEqual(session.selectedModelID, "qwen3:8b")
        XCTAssertEqual(selection.lastModel(forProfile: studio.id), "qwen3-32b", "each server keeps its own choice")
    }

    /// A remembered name the target server does not serve would fail the turn, so the session
    /// falls back to a model the server really reported rather than sending a stranger.
    func testAModelNameIsNeverCarriedToAServerThatDoesNotHaveIt() async throws {
        let selection = ServerSelectionModel(storing: RecordingSelectionStore())
        let session = makeSession(selection, studioModels: ["gemma-3n-e4b"])

        session.select(serverProfileID: home.id)
        await settle(session, models: 2)
        session.choose(model: "qwen3:8b")

        session.select(serverProfileID: studio.id)
        await settle(session, models: 1)
        XCTAssertEqual(session.selectedModelID, "gemma-3n-e4b")
        XCTAssertEqual(selection.lastModel(forProfile: home.id), "qwen3:8b", "the other server keeps its own name")
    }

    /// Two servers can serve a model with the same name, so the choice is keyed by profile:
    /// picking one on a server must not silently pick it on the other.
    func testTwoServersWithTheSameModelNameKeepSeparateChoices() {
        let selection = ServerSelectionModel(storing: RecordingSelectionStore())
        let shared = ["llama3.2:3b", "qwen3:8b"]
        let session = makeSession(selection, homeModels: shared, studioModels: shared)

        session.apply(serverProfileID: home.id)
        session.choose(model: "qwen3:8b")
        session.apply(serverProfileID: studio.id)
        session.choose(model: "llama3.2:3b")

        XCTAssertEqual(selection.lastModel(forProfile: home.id), "qwen3:8b")
        XCTAssertEqual(selection.lastModel(forProfile: studio.id), "llama3.2:3b")
    }

    /// The mock is not a saved server: it gets its own model, not the one typed for a machine
    /// across the room — and choosing it must not move the shared server choice.
    func testANonServerEngineTakesItsOwnModelAndKeepsTheServerChoice() async throws {
        let selection = ServerSelectionModel(storing: RecordingSelectionStore())
        let session = makeSession(selection)
        session.select(serverProfileID: home.id)
        await settle(session, models: 2)
        session.choose(model: "qwen3:8b")

        session.select(providerID: "mock")
        await wait { session.availableModels.first?.id == "cairn-mock-8b" }

        XCTAssertEqual(session.selectedProviderID, "mock")
        XCTAssertEqual(session.selectedModelID, "cairn-mock-8b", "a server's model name never rides over to the mock")
        XCTAssertEqual(selection.activeProfileID, home.id, "the mock is not a server, so the server choice stands")
        XCTAssertEqual(selection.lastModel(forProfile: home.id), "qwen3:8b")
    }

    /// A profile with no registered engine cannot be repointed at, so nothing moves.
    func testAServerWithNoEngineLeavesTheSessionPointedWhereItWas() async throws {
        let selection = ServerSelectionModel(storing: RecordingSelectionStore())
        let session = makeSession(selection)
        session.select(serverProfileID: home.id)
        await settle(session, models: 2)
        let before = session.selectedProviderID

        session.apply(serverProfileID: UUID())

        XCTAssertEqual(session.selectedProviderID, before, "there is no engine to repoint at")
        XCTAssertEqual(session.availableModels.map(\.id), ["llama3.2:3b", "qwen3:8b"])
    }

    /// A session built without a selection store — the offline mock wiring — still switches;
    /// it simply remembers nothing.
    func testSwitchingWithoutASelectionStoreStillWorks() async throws {
        let session = makeSession(nil)

        session.select(serverProfileID: studio.id)
        await settle(session, models: 1)

        XCTAssertEqual(session.selectedProviderID, studio.engineID)
        XCTAssertEqual(session.selectedModelID, "qwen3-32b")
        XCTAssertNil(session.selection)
    }

    // MARK: - Waiting

    /// `select(serverProfileID:)` refetches the catalog on a task, so a test waits for the switch
    /// to land instead of sleeping a fixed amount — a fixed sleep is what makes a suite flake.
    private func settle(_ session: ChatSessionModel, models: Int) async {
        await wait { session.availableModels.count == models }
    }

    private func wait(
        until condition: @escaping @MainActor () -> Bool,
        ticks: Int = 400
    ) async {
        for _ in 0..<ticks where !condition() {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}

