import XCTest
import CairnChatDomain
import CairnAppUI
import CairnProviderRemote

/// The Web Search screen's write path, against two separate in-memory vaults.
///
/// Two vaults exist for one reason: a SearXNG token and an Ollama Cloud token must never end up in the same
/// place, because the row that reads one is allowed to send queries out and the row that reads the other is a
/// model server's bearer token. With one memory store standing in for each, a leak from one to the other shows
/// up as an assertion instead of as a token in a request it was never meant to sign.
///
/// The token field's three states are the second reason: nil means "leave it alone", "" means "remove it", and
/// a value means "replace it". A screen that read the stored token back would make an edit of a name into a
/// silent rewrite of a credential.
@MainActor
final class WebSearchSettingsModelTests: XCTestCase {
    private let tokenShape = WebSearchCredentialShape.secretHeader(name: "X-API-Key")

    /// A nested type does **not** inherit the outer test class's actor isolation, so this one says so
    /// itself: `ThemeModel` and `WebSearchSettingsModel` are main-actor types, and building them from a
    /// nonisolated `init` is an error rather than a warning.
    @MainActor
    private final class Fixtures {
        let theme: ThemeModel
        let searchVault = MemorySecretStore()
        let serverVault = MemorySecretStore()
        let model: WebSearchSettingsModel

        init(settings: AppSettings = .default) {
            theme = ThemeModel(settings: settings)
            model = WebSearchSettingsModel(
                theme: theme, searchSecrets: searchVault, serverSecrets: serverVault, testing: nil
            )
        }
    }

    private func fixtures(withOutbound acknowledgment: Bool = true) -> Fixtures {
        var settings = AppSettings.default
        settings.setOutboundWebAllowed(acknowledgment)
        return Fixtures(settings: settings)
    }

    private func boxEdit(token: String? = "s3cr3t", id: UUID? = nil) -> WebSearchRowEdit {
        WebSearchRowEdit(
            id: id, name: "Box", address: "http://192.168.1.20:8888",
            categories: [], language: "", timeoutSeconds: 8,
            credentialShape: tokenShape, token: token, customHeaders: [:]
        )
    }

    func testASearchTokenGoesToTheSearchVaultAndNowhereElse() throws {
        let box = fixtures()
        XCTAssertTrue(box.model.save(boxEdit()))
        let stored = try XCTUnwrap(box.model.rows.first { $0.displayName == "Box" })
        XCTAssertEqual(box.model.credential(for: stored), "s3cr3t")
        XCTAssertEqual(box.searchVault.items.count, 1, "the search vault holds it")
        XCTAssertTrue(box.serverVault.items.isEmpty, "and the model server's vault never saw it")
        XCTAssertTrue(stored.hasCredential, "the row says a token exists, and only that")
    }

    /// The stored value is never put back into the field, so an edit that never touches the token field cannot
    /// have meant to change it. nil in, no vault write, token still there.
    func testRenamingARowLeavesTheStoredTokenAlone() {
        let box = fixtures()
        XCTAssertTrue(box.model.save(boxEdit()))
        let row = box.model.rows.first { $0.displayName == "Box" }
        XCTAssertNil(WebSearchRowEdit(row: row!).token, "the field opens empty, never reading the vault back")

        var rename = WebSearchRowEdit(row: row!)
        rename.name = "Box Two"
        rename.token = nil
        XCTAssertTrue(box.model.save(rename))
        XCTAssertEqual(box.model.credential(for: box.model.rows.first { $0.id == row!.id }!), "s3cr3t")
    }

    func testAnEmptyTokenFieldIsARequestToRemoveTheCredential() {
        let box = fixtures()
        XCTAssertTrue(box.model.save(boxEdit()))
        let row = box.model.rows.first { $0.displayName == "Box" }!

        var cleared = WebSearchRowEdit(row: row)
        cleared.token = ""
        XCTAssertTrue(box.model.save(cleared))

        let after = box.model.rows.first { $0.id == row.id }!
        XCTAssertFalse(after.hasCredential)
        XCTAssertNil(box.model.credential(for: after))
        XCTAssertTrue(box.searchVault.items.isEmpty, "removed means removed from the vault too")
    }


    /// An address edit points the same row at a different machine. The permission was given to the box on the
    /// kitchen shelf, not to whatever answers that hostname next, so the grant does not travel.
    func testMovingARowToANewAddressTakesThePermissionBack() throws {
        let box = fixtures()
        XCTAssertTrue(box.model.save(boxEdit()))
        let row = try XCTUnwrap(box.model.rows.first { $0.displayName == "Box" })
        var search = box.theme.settings.webSearch
        search.consent.grant(row)
        box.theme.setWebSearch(search)
        XCTAssertEqual(box.model.consent(for: row), .granted)

        var moved = WebSearchRowEdit(row: row)
        moved.address = "http://192.168.1.20:8889"
        moved.token = nil
        XCTAssertTrue(box.model.save(moved))

        let after = try XCTUnwrap(box.model.rows.first { $0.id == row.id })
        XCTAssertEqual(box.model.consent(for: after), .undecided, "the next search asks again")
        XCTAssertEqual(box.model.credential(for: after), "s3cr3t", "while the credential stays put")
    }

    func testDeletingARowTakesItsTokenAndItsPermissionWithIt() throws {
        let box = fixtures()
        XCTAssertTrue(box.model.save(boxEdit()))
        let row = try XCTUnwrap(box.model.rows.first { $0.displayName == "Box" })
        var search = box.theme.settings.webSearch
        search.consent.grant(row)
        box.theme.setWebSearch(search)
        XCTAssertTrue(box.model.remove(row))

        XCTAssertFalse(box.model.rows.contains { $0.id == row.id })
        XCTAssertTrue(box.searchVault.items.isEmpty, "no orphaned credential behind a deleted row")
        XCTAssertEqual(box.theme.settings.webSearch.consentDecision(for: row), .undecided)
        XCTAssertNotNil(box.model.revertNoticeText, "the active row vanished, and that is said out loud")
    }

    func testTheBuiltInRowRefusesDeletionAndStaysListed() throws {
        let box = fixtures()
        let builtIn = try XCTUnwrap(box.model.rows.first { $0.kind == .duckDuckGo })
        XCTAssertFalse(box.model.remove(builtIn), "there is always a row selected, so there is always a row")
        XCTAssertTrue(box.model.rows.contains { $0.id == builtIn.id })
    }

    /// The badge is a standing condition, not a receipt: it is up whenever the selected row is beyond the user's
    /// own network and the tools are on. A LAN row selected must take it down, or the badge becomes noise.
    func testTheBadgeFollowsTheSelectedRowAndTheSwitch() throws {
        let box = fixtures()
        XCTAssertTrue(box.model.badgeShowsImmediately, "DuckDuckGo selected with the tools on")
        XCTAssertTrue(box.model.badgeDetail.contains("DuckDuckGo"))

        XCTAssertTrue(box.model.save(boxEdit()))
        let lan = try XCTUnwrap(box.model.rows.first { $0.displayName == "Box" })
        box.model.select(id: lan.id)
        XCTAssertFalse(box.model.badgeShowsImmediately, "nothing leaves the house, so nothing is flagged")

        box.theme.setOutboundWebAllowed(false)
        XCTAssertFalse(box.model.badgeShowsImmediately)
    }

    func testTheResultCountCannotBeSetOutsideTheRange() {
        let box = fixtures()
        box.model.setResultCount(999)
        XCTAssertEqual(box.model.resultCount, WebSearchProviderProfile.resultCountRange.upperBound)
        box.model.setResultCount(0)
        XCTAssertEqual(box.model.resultCount, WebSearchProviderProfile.resultCountRange.lowerBound)
    }
}
