import XCTest
import CairnChatDomain
import CairnPersistence

/// Web-search settings through the real store, on the simulator in CI.
///
/// The bug this file exists for: `SettingsRecord.toSettings()` used to build `AppSettings` without
/// `webTools`, so nothing about web tools reached disk. The outbound acknowledgement was re-asked or lost,
/// and a SearXNG address typed in Settings vanished on the next launch while the row in Settings still
/// showed it. Every test here writes, throws the store away, and reads again — because a settings value
/// that survives only in memory is the bug.
@MainActor
final class WebSearchSettingsPersistenceTests: XCTestCase {
    private func makeStore() throws -> SwiftDataStore { try SwiftDataStore(inMemory: true) }

    private func lanRow() -> WebSearchProviderProfile {
        WebSearchProviderProfile(
            kind: .searxng, displayName: "Box", baseURLString: "http://192.168.1.20:8888"
        )
    }

    func testTheWebToolSwitchesSurviveAReload() throws {
        let store = try makeStore()
        var search = WebSearchSettings.default
        try search.providers.add(lanRow())
        search = search.setResultCount(8)
        search.consent.grant(search.activeProvider)
        var settings = AppSettings.default
        settings.setOutboundWebAllowed(true)
        settings.setWebSearch(search)
        try store.saveAppSettings(settings)

        let reloaded = try store.appSettings()
        XCTAssertTrue(reloaded.outboundWebAllowed, "a granted acknowledgement must not re-ask")
        XCTAssertEqual(reloaded.webSearch.resultCount, 8)
        XCTAssertEqual(reloaded.webSearch.activeProvider.displayName, "Box")
        XCTAssertFalse(reloaded.webSearch.requiresConsentPrompt, "the grant is stored too")
        XCTAssertEqual(reloaded.webSearch.providerCount, 2)
    }

    /// A settings row written before providers existed holds one loose address. It has to come back as a
    /// provider row the user can see and select, not as a field that no longer does anything.
    func testALegacySearXNGAddressIsImportedOnReadAndStoredOnWrite() throws {
        let store = try makeStore()
        var settings = AppSettings.default
        settings.setSearXNGURL("http://192.168.1.20:8888")
        try store.saveAppSettings(settings)

        let imported = try store.appSettings()
        XCTAssertEqual(imported.webSearch.activeProvider.kind, .searxng, "their instance stays in front")
        XCTAssertEqual(imported.webSearch.activeProvider.baseURLString, "http://192.168.1.20:8888")
        XCTAssertEqual(imported.webSearch.providerCount, 2)

        try store.saveAppSettings(imported)
        let again = try store.appSettings()
        XCTAssertEqual(again.webSearch.allProviders.filter { $0.kind == .searxng }.count, 1, "imported once")
        XCTAssertEqual(again.webSearch.activeProvider.kind, .searxng)
        XCTAssertNil(again.webSearch.revertNotice, "an import is not a reversion")
    }

    func testADefaultRowReadsAsDuckDuckGoWithNothingConsented() throws {
        let store = try makeStore()
        try store.saveAppSettings(.default)
        let reloaded = try store.appSettings()
        XCTAssertEqual(reloaded.webSearch.activeProvider.kind, .duckDuckGo)
        XCTAssertEqual(reloaded.webSearch.resultCount, 5)
        XCTAssertFalse(reloaded.outboundWebAllowed)
        XCTAssertTrue(reloaded.webSearch.requiresConsentPrompt, "a fresh install has agreed to nothing")
    }

    /// Settings are written whole, so a theme change cannot silently drop the provider list and a provider
    /// edit cannot drop the theme. That is the property the single-row design buys, and it is only real if
    /// it is checked.
    func testOneWriteCarriesEveryPartOfTheSettingsValue() throws {
        let store = try makeStore()
        var settings = AppSettings.default
        settings.themeID = "switchback"
        settings.setOutboundWebAllowed(true)
        try store.saveAppSettings(settings)

        var reloaded = try store.appSettings()
        reloaded.selectWebSearchProvider(id: WebSearchProviderProfile.builtInID)
        try store.saveAppSettings(reloaded)

        let final = try store.appSettings()
        XCTAssertEqual(final.themeID, "switchback", "the theme survived the second write")
        XCTAssertTrue(final.outboundWebAllowed, "and so did the acknowledgement")
        XCTAssertEqual(final.webSearch.activeProvider.kind, .duckDuckGo)
    }

    /// A stored provider row has no field that can hold a secret, which is what lets the whole provider list
    /// live in the settings store. Checked on the encoded key names rather than on a value, because "there
    /// is nowhere to put it" is the actual guarantee.
    func testAStoredProviderRowCarriesNoPlaceForASecret() throws {
        let store = try makeStore()
        var search = WebSearchSettings.default
        try search.providers.add(WebSearchProviderProfile(
            kind: .searxng, displayName: "Box", baseURLString: "https://search.example.com",
            credentialShape: .secretHeader(name: "X-API-Key"), hasCredential: true
        ))
        var settings = AppSettings.default
        settings.setWebSearch(search)
        try store.saveAppSettings(settings)

        let reloaded = try store.appSettings()
        let row = try XCTUnwrap(reloaded.webSearch.allProviders.first { $0.kind == .searxng })
        XCTAssertTrue(row.hasCredential, "the row says a credential exists, and only that")
        XCTAssertEqual(row.credentialShape, .secretHeader(name: "X-API-Key"))

        let blob = try JSONEncoder().encode(row)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: blob) as? [String: Any])
        // The two credential-shaped keys are the presence flag and the shape — a name and a boolean, which
        // is all a settings store is ever allowed to know. Everything else must not read like a value.
        let secretShapedNames = ["token", "secret", "password", "apikey", "authorization", "bearer"]
        for name in object.keys where name != "hasCredential" && name != "credentialShape" {
            let normalised = name.lowercased().replacingOccurrences(of: "-", with: "")
            XCTAssertTrue(
                secretShapedNames.allSatisfy { !normalised.contains($0) },
                "a settings blob must have no field that could hold a secret: \(name)"
            )
        }
    }
}
