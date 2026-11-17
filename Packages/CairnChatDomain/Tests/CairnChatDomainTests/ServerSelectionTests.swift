import XCTest
@testable import CairnChatDomain

/// Selection is keyed by profile UUID, never by model name: two servers can both have a model
/// called `llama3`, and switching between them must not carry a choice to a machine that does not
/// have it. These are the rules the Servers screen and the chat both read.
@MainActor
final class ServerSelectionTests: XCTestCase {

    private func profile(
        named name: String,
        enabled: Bool = true,
        optIn: Bool = false
    ) -> ServerProfile {
        var made = ServerProfile(
            name: name,
            kind: .ollama,
            baseURLString: "http://192.168.1.20:11434",
            enabled: enabled,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        made.publicInternetOptIn = optIn
        return made
    }

    func testLastModelIsRememberedPerServer() {
        let home = UUID(), work = UUID()
        var selection = ServerSelection()
        selection.remember(modelID: "llama3", forProfile: home)
        selection.remember(modelID: "qwen2.5", forProfile: work)

        XCTAssertEqual(selection.lastModel(forProfile: home), "llama3")
        XCTAssertEqual(selection.lastModel(forProfile: work), "qwen2.5")
        XCTAssertNil(selection.lastModel(forProfile: UUID()))
    }

    func testForgettingAServerClearsItsPointerAndItsModel() {
        let home = UUID()
        var selection = ServerSelection()
        selection.setActive(home)
        selection.remember(modelID: "llama3", forProfile: home)
        selection.forgetProfile(home)

        XCTAssertNil(selection.activeProfileID)
        XCTAssertNil(selection.lastModel(forProfile: home))
    }

    func testResolvedActiveFallsBackWhenTheStoredChoiceCannotAnswer() {
        let home = profile(named: "Home box")
        let work = profile(named: "Work box")
        var selection = ServerSelection()
        selection.setActive(home.id)

        XCTAssertEqual(selection.resolvedActive(in: [home, work])?.id, home.id)

        // Switched off: the choice falls forward to something that can actually answer.
        var off = home
        off.enabled = false
        XCTAssertEqual(selection.resolvedActive(in: [off, work])?.id, work.id)

        // Deleted entirely.
        XCTAssertEqual(selection.resolvedActive(in: [work])?.id, work.id)
        XCTAssertNil(selection.resolvedActive(in: []))
    }

    /// A hosted server is only reachable with the outbound opt-in, so it must not be the resolved
    /// choice without one — and must win it back the moment the opt-in is given.
    func testResolvedActiveRefusesAPublicServerWithNoOutboundOptIn() {
        var cloud = ServerProfile(
            name: "Hosted",
            kind: .ollamaCloud,
            baseURLString: "https://ollama.com",
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let lan = profile(named: "Home box")
        var selection = ServerSelection()
        selection.setActive(cloud.id)

        XCTAssertFalse(cloud.usableNow)
        XCTAssertEqual(selection.resolvedActive(in: [cloud, lan])?.id, lan.id)

        cloud.publicInternetOptIn = true
        XCTAssertTrue(cloud.usableNow)
        XCTAssertEqual(selection.resolvedActive(in: [cloud, lan])?.id, cloud.id)
    }

    func testSelectionSurvivesAReloadThroughTheStore() {
        let store = FakeSelectionStore()
        let model = ServerSelectionModel(storing: store)
        let home = profile(named: "Home box")

        model.setActive(home.id)
        model.remember(modelID: "llama3", forProfile: home.id)

        var reloaded = ServerSelectionModel(storing: store)
        reloaded.reload()
        XCTAssertEqual(reloaded.activeProfileID, home.id)
        XCTAssertEqual(reloaded.lastModel(forProfile: home.id), "llama3")

        // Forgetting writes through, so a recycled UUID cannot inherit an old choice.
        model.forget(home.id)
        reloaded = ServerSelectionModel(storing: store)
        reloaded.reload()
        XCTAssertNil(reloaded.activeProfileID)
        XCTAssertNil(reloaded.lastModel(forProfile: home.id))
    }
}

@MainActor
private final class FakeSelectionStore: ServerSelectionStoring {
    var stored = ServerSelection()

    func selection() throws -> ServerSelection { stored }

    func saveSelection(_ selection: ServerSelection) throws { stored = selection }
}
