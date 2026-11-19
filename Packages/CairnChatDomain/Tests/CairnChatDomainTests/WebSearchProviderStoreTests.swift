import Foundation
import XCTest
@testable import CairnChatDomain

/// The provider list, the selection, and the rules that keep both honest.
///
/// These tests are mostly about the two failures a settings screen cannot see: a list that loses its
/// built-in row, and a selection that quietly moves. Both would change where the user's queries go with
/// nothing on screen saying so.
final class WebSearchProviderStoreTests: XCTestCase {
    private func row(_ name: String, _ endpoint: String) -> WebSearchProviderProfile {
        WebSearchProviderProfile(kind: .searxng, displayName: name, baseURLString: endpoint)
    }

    /// The documented example LAN address, and a public host that must be https.
    private let lan = "http://192.168.1.20:8888"
    private let remote = "https://search.example.com/searxng"

    func testAFreshInstallHasOneProviderAndItIsDuckDuckGo() {
        let store = WebSearchProviderStore.default
        XCTAssertEqual(store.providers.map(\.kind), [.duckDuckGo])
        XCTAssertEqual(store.active.kind, .duckDuckGo)
        XCTAssertTrue(store.active.reachesPublicInternet, "DuckDuckGo is a third party, and is named as one")
        XCTAssertNil(store.revertNotice, "nothing has moved, so there is nothing to explain")
    }

    func testAddingAProviderMakesItActiveBecauseThatIsTheOnlyReasonToAddOne() throws {
        var store = WebSearchProviderStore.default
        try store.add(row("Box", remote))
        XCTAssertEqual(store.userRows.count, 1)
        XCTAssertEqual(store.active.displayName, "Box")
        XCTAssertNil(store.revertNotice, "the user chose this, so nothing was reverted")
    }

    func testTheBuiltInRowRefusesToBeDeleted() {
        var store = WebSearchProviderStore.default
        XCTAssertThrowsError(try store.remove(id: WebSearchProviderProfile.builtInID)) { error in
            XCTAssertEqual(error as? WebSearchProviderValidationError, .builtInIsPermanent)
        }
        XCTAssertEqual(store.providers.count, 1)
    }

    func testDeletingTheActiveRowRevertsToDuckDuckGoAndSaysWhy() throws {
        var store = WebSearchProviderStore.default
        let added = row("Box", remote)
        try store.add(added)
        let removed = try store.remove(id: added.id)
        XCTAssertEqual(removed?.displayName, "Box")
        XCTAssertEqual(store.active.kind, .duckDuckGo)
        let notice = try XCTUnwrap(store.revertNotice)
        XCTAssertEqual(notice.reason, .providerRemoved)
        XCTAssertTrue(notice.text.contains("Box"), "the notice names what is gone")
        XCTAssertTrue(notice.text.contains("DuckDuckGo"), "and where the queries go now")
        store.dismissRevertNotice()
        XCTAssertNil(store.revertNotice, "dismissing is a user action, not a timeout")
    }

    func testDeletingTheRowTheUserIsActuallyUsingLeavesTheOtherOneSelected() throws {
        var store = WebSearchProviderStore.default
        let first = row("First", remote)
        let second = row("Second", lan)
        try store.add(first)
        try store.add(second)
        try store.select(id: first.id)
        try store.remove(id: second.id)
        XCTAssertEqual(store.active.displayName, "First")
        XCTAssertNil(store.revertNotice)
    }

    func testAStaleSelectionFallsBackInsteadOfSearchingSomethingNobodyPicked() {
        var store = WebSearchProviderStore.default
        store.select(id: UUID())
        XCTAssertEqual(store.active.kind, .duckDuckGo)
        XCTAssertEqual(store.revertNotice?.reason, .selectionLost)
    }

    /// A row cannot change what kind of provider it is: `kind` is a `let`, and the only other way into the
    /// list is `add`. That matters for consent, which is keyed on kind plus id — a row that could be
    /// re-pointed at a different kind of backend would carry its old grant with it.
    func testAnEditCannotTurnARowIntoADifferentThirdParty() throws {
        var store = WebSearchProviderStore.default
        let added = row("Box", remote)
        try store.add(added)
        // The address may move within the same kind, but moving to a public host over plain http is refused
        // rather than reinterpreted as "now this row means something else".
        XCTAssertThrowsError(
            try store.update(id: added.id) { $0.baseURLString = "http://search.example.com" }
        ) { error in
            XCTAssertEqual(error as? WebSearchProviderValidationError, .plaintextPublicInternet)
        }
        XCTAssertEqual(store.active.baseURLString, remote, "the refused edit left the row untouched")
    }

    func testAnEditThatKeepsTheRowValidLandsAndStampsTheChange() throws {
        var store = WebSearchProviderStore.default
        let added = row("Box", remote)
        try store.add(added)
        let later = Date(timeIntervalSinceNow: 60)
        try store.update(id: added.id, now: later) { $0.displayName = "Home box" }
        XCTAssertEqual(store.active.displayName, "Home box")
        XCTAssertGreaterThan(store.active.updatedAt, store.active.createdAt)
    }
}
