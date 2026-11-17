import XCTest
import CairnChatDomain
import CairnPersistence

/// Which server is answering, and what each server was last used with, has to survive a relaunch —
/// a switch that evaporates on quit is not a switch. These run on the simulator against real
/// SwiftData through `SwiftDataStore`, which is the app's own conformer of
/// `ServerSelectionStoring`, so what is proven here is the path the app actually takes: the choice
/// is read back from the row rather than from whatever the view model is holding.
@MainActor
final class ServerSelectionTests: XCTestCase {

    private func makeStore() throws -> SwiftDataStore { try SwiftDataStore(inMemory: true) }

    private func server(_ name: String, port: Int) -> ServerProfile {
        ServerProfile(name: name, kind: .ollama, baseURLString: "http://192.168.1.20:\(port)")
    }

    func testActiveServerAndLastModelPerServerSurviveAReload() throws {
        let store = try makeStore()
        let studio = server("Studio", port: 1234)
        let box = server("Box", port: 11434)
        try store.save(studio)
        try store.save(box)

        let selection = ServerSelectionModel(storing: store)
        selection.setActive(box.id)
        selection.remember(modelID: "qwen3:8b", forProfile: box.id)
        selection.remember(modelID: "qwen3-32b", forProfile: studio.id)

        // Read the row, not what the view model happens to be holding.
        selection.reload()
        XCTAssertNil(selection.lastError)
        XCTAssertEqual(selection.activeProfileID, box.id, "the server that was pointed at is still pointed at")
        XCTAssertEqual(selection.lastModel(forProfile: box.id), "qwen3:8b")
        XCTAssertEqual(selection.lastModel(forProfile: studio.id), "qwen3-32b")
    }

    func testAFreshStoreHasNothingChosen() throws {
        let selection = ServerSelectionModel(storing: try makeStore())
        XCTAssertNil(selection.activeProfileID, "no server is active before the user picks one")
        XCTAssertTrue(selection.selection.lastModelIDs.isEmpty)
    }

    /// Two servers can offer models by the same name, so the memory is keyed by server, not by name.
    func testEachServerKeepsItsOwnLastModel() throws {
        let store = try makeStore()
        let first = server("First", port: 11434)
        let second = server("Second", port: 1234)
        try store.save(first)
        try store.save(second)

        let selection = ServerSelectionModel(storing: store)
        selection.remember(modelID: "qwen3:8b", forProfile: first.id)
        selection.remember(modelID: "llama3.2:3b", forProfile: second.id)
        selection.remember(modelID: "qwen3:14b", forProfile: first.id)

        selection.reload()
        XCTAssertEqual(selection.lastModel(forProfile: first.id), "qwen3:14b", "the newer choice wins for that server")
        XCTAssertEqual(selection.lastModel(forProfile: second.id), "llama3.2:3b", "and nothing moves on the other one")
    }

    func testADeletedServerLeavesNoTraceInTheChoice() throws {
        let store = try makeStore()
        let gone = server("Going away", port: 11434)
        let kept = server("Staying", port: 1234)
        try store.save(gone)
        try store.save(kept)

        let selection = ServerSelectionModel(storing: store)
        selection.setActive(gone.id)
        selection.remember(modelID: "qwen3:8b", forProfile: gone.id)
        selection.remember(modelID: "gemma3", forProfile: kept.id)

        try store.delete(id: gone.id)

        selection.reload()
        XCTAssertNil(selection.activeProfileID, "a pointer at a server that no longer exists cannot stay active")
        XCTAssertNil(selection.lastModel(forProfile: gone.id), "a remembered model must not outlive its server")
        XCTAssertEqual(selection.lastModel(forProfile: kept.id), "gemma3", "the surviving server keeps its own memory")
    }

    /// The read path prunes even when a caller never said `forget`, because "no trace of a deleted
    /// server" has to hold after a relaunch, not only when the app remembers to ask.
    func testTheReadPathPrunesAChoiceThatPointsAtNothing() throws {
        let store = try makeStore()
        let orphan = UUID()
        try store.saveSelection(
            ServerSelection(activeProfileID: orphan, lastModelIDs: [orphan: "qwen3:8b"])
        )

        let read = try store.selection()
        XCTAssertNil(read.activeProfileID)
        XCTAssertTrue(read.lastModelIDs.isEmpty)
    }

    /// Repeated writes update the one choice rather than merging an older one back in: the row is
    /// keyed by a fixed slot, so there is never a second answer to "which server is active".
    func testRepeatedWritesLeaveOneChoiceRatherThanTwo() throws {
        let store = try makeStore()
        let first = server("First", port: 11434)
        let second = server("Second", port: 1234)
        try store.save(first)
        try store.save(second)

        try store.saveSelection(
            ServerSelection(activeProfileID: first.id, lastModelIDs: [first.id: "qwen3:8b"])
        )
        try store.saveSelection(ServerSelection(activeProfileID: second.id))

        let read = try store.selection()
        XCTAssertEqual(read.activeProfileID, second.id, "the newest write is the choice")
        XCTAssertTrue(read.lastModelIDs.isEmpty, "an older write does not reappear under the new one")
    }

    /// The app's schema carries the selection row alongside the chat and the profiles: one
    /// container, one writer, so a server switch cannot race a profile write.
    func testTheAppSchemaCarriesTheSelectionNextToTheChat() throws {
        let store = try makeStore()
        try store.createConversation(
            title: "Choice", mode: .onDeviceOnly, config: .default, isTemporary: false
        )
        let box = server("Box", port: 11434)
        try store.save(box)

        let selection = ServerSelectionModel(storing: store)
        selection.setActive(box.id)
        selection.remember(modelID: "qwen3:8b", forProfile: box.id)

        let reopened = ServerSelectionModel(storing: store)
        XCTAssertEqual(reopened.activeProfileID, box.id)
        XCTAssertEqual(reopened.lastModel(forProfile: box.id), "qwen3:8b")
        XCTAssertEqual(try store.loadConversations().count, 1, "and the chat is still there next to it")
    }
}

