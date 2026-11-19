import Foundation
import XCTest
@testable import CairnChatDomain

/// Decoding and the Ollama Cloud reconciliation: the two paths into the provider list that nobody tapped.
///
/// A blob written by another build, and a key that appeared or vanished in the server list, both change the
/// list without going through the editor. Each has to end in a list that can still search, and in a
/// selection the user can account for.
final class WebSearchProviderStoreDecodingTests: XCTestCase {
    func testAnEmptyBlobStillHasTheBuiltInRow() throws {
        let decoded = try JSONDecoder().decode(
            WebSearchProviderStore.self, from: Data(#"{"providers":[]}"#.utf8)
        )
        XCTAssertEqual(decoded.providers.map(\.kind), [.duckDuckGo])
        XCTAssertEqual(decoded.active.kind, .duckDuckGo)
        XCTAssertNil(decoded.revertNotice, "nothing was selected before, so nothing was lost")
    }

    /// A blob written by another build (or another device) can name a row this one has never seen. It has
    /// to come back searchable, and it has to say that the ground moved.
    func testASelectionThatNamesNothingIsReportedRatherThanSilentlyMoved() throws {
        let unknown = "6C1B1D3E-3C9E-4F1E-9F0E-7A6B5C4D3E2F"
        let json = #"{"providers":[],"activeProviderID":"\#(unknown)"}"#
        let revived = try JSONDecoder().decode(
            WebSearchProviderStore.self, from: Data(json.utf8)
        )
        XCTAssertEqual(revived.active.kind, .duckDuckGo)
        XCTAssertEqual(revived.revertNotice?.reason, .selectionLost)
    }

    func testADecodedStoreKeepsTheRowsItKnowsAndPutsTheBuiltInRowFirst() throws {
        var source = WebSearchProviderStore.default
        try source.add(
            WebSearchProviderProfile(
                kind: .searxng, displayName: "Box", baseURLString: "http://127.0.0.1:8888"
            )
        )
        let blob = try JSONEncoder().encode(source)
        let revived = try JSONDecoder().decode(WebSearchProviderStore.self, from: blob)
        XCTAssertEqual(revived.providers.count, 2)
        XCTAssertEqual(revived.providers.first?.kind, .duckDuckGo)
    }

    func testACloudRowAppearsWithAKeyAndDisappearsWithoutIt() {
        var store = WebSearchProviderStore.default
        let profile = UUID()
        store.sync(cloudMirrors: [
            WebSearchCloudMirror(sourceProfileID: profile, profileName: "Cloud", hasKey: true)
        ])
        let cloud = store.providers.filter { $0.kind == .ollamaCloud }
        XCTAssertEqual(cloud.count, 1)
        XCTAssertEqual(cloud.first?.displayName, "Ollama Cloud — Cloud")
        XCTAssertEqual(cloud.first?.baseURLString, WebSearchProviderKind.ollamaCloudEndpoint)
        XCTAssertEqual(cloud.first?.networkClass, .publicInternet)
        XCTAssertTrue(cloud.first?.hasCredential ?? false)

        store.select(id: cloud[0].id)
        store.sync(cloudMirrors: [
            WebSearchCloudMirror(sourceProfileID: profile, profileName: "Cloud", hasKey: false)
        ])
        XCTAssertTrue(store.providers.filter { $0.kind == .ollamaCloud }.isEmpty)
        XCTAssertEqual(store.active.kind, .duckDuckGo)
        XCTAssertEqual(store.revertNotice?.reason, .cloudKeyRemoved)
    }

    /// Reconciliation is run on every settings change, so running it twice must be invisible. A row that
    /// duplicated on each pass would leave two providers pointing at one account, and a re-sync that stamps
    /// `updatedAt` would move a row's "last edited" time while the user edited nothing.
    func testReconcilingCloudRowsTwiceChangesNothing() {
        let mirror = WebSearchCloudMirror(sourceProfileID: UUID(), profileName: "Cloud", hasKey: true)
        var store = WebSearchProviderStore.default
        store.sync(cloudMirrors: [mirror])
        let afterFirst = store
        store.sync(cloudMirrors: [mirror])
        store.sync(cloudMirrors: [mirror])
        XCTAssertEqual(store, afterFirst, "a re-sync must change nothing at all")
        XCTAssertEqual(store.providers.filter { $0.kind == .ollamaCloud }.count, 1)
        XCTAssertEqual(store.activeProviderID, afterFirst.activeProviderID)
    }

    /// A rename in the server list has to reach the row, or Settings shows a provider named after a profile
    /// that no longer exists under that name.
    func testACloudRowFollowsTheProfileItMirrors() {
        var store = WebSearchProviderStore.default
        let mirror = WebSearchCloudMirror(sourceProfileID: UUID(), profileName: "Cloud", hasKey: true)
        store.sync(cloudMirrors: [mirror])
        store.sync(cloudMirrors: [
            WebSearchCloudMirror(sourceProfileID: mirror.sourceProfileID, profileName: "Work", hasKey: true)
        ])
        let cloud = store.providers.filter { $0.kind == .ollamaCloud }
        XCTAssertEqual(cloud.count, 1)
        XCTAssertEqual(cloud.first?.displayName, "Ollama Cloud — Work")
    }
}
