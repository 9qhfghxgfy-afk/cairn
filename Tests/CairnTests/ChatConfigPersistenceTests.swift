import XCTest
import CairnChatDomain
@testable import CairnPersistence

/// P2 persistence: the per-chat configuration, the app-wide settings, and the row a pre-P2 build
/// left behind. These live in the Xcode target because SwiftData needs a real runtime.
@MainActor
final class ChatConfigPersistenceTests: XCTestCase {

    private var configured: ChatConfig {
        ChatConfig(
            persona: "Be terse.",
            sampling: SamplingConfig(
                temperature: 0.2, topP: 0.8, minP: 0.05, topK: 40, maxTokens: 512,
                repeatPenalty: 1.35, seed: .fixed(42), contextWindow: 8192
            ),
            context: ContextToggleSet(date: true, timeAndTimezone: true, responseFormat: false),
            responseFormat: .terse,
            thinkingEnabled: true
        )
    }

    /// Every part survives: persona, each knob, the toggles, the format. A chat that reopened with
    /// different knobs would answer differently with nothing on screen to say so.
    func testChatConfigSurvivesAReload() throws {
        let store = try SwiftDataStore(inMemory: true)
        let created = try store.createConversation(
            title: "Configured", mode: .remoteOnly, config: configured, isTemporary: false
        )
        let reloaded = try store.conversation(id: created.id)
        XCTAssertEqual(reloaded?.config, configured)
        XCTAssertEqual(reloaded?.config.configuredOptionCount, 8)
        XCTAssertEqual(reloaded?.mode, .remoteOnly)
        XCTAssertFalse(reloaded?.isTemporary ?? true, "nothing on disk is ever temporary")
    }

    /// An unset knob must read back as unset, not as the shipped number: "I did not ask" and "I asked
    /// for 0.8" are different states, and a store that fills the gap takes the knob away from the
    /// server's own default without anyone choosing that.
    func testUnsetKnobsStayUnsetAcrossAReload() throws {
        let store = try SwiftDataStore(inMemory: true)
        let created = try store.createConversation(
            title: "Bare", mode: .onDeviceOnly, config: .bare, isTemporary: false
        )
        let reloaded = try store.conversation(id: created.id)
        XCTAssertEqual(reloaded?.config.sampling, .unset)
        XCTAssertEqual(reloaded?.config.configuredOptionCount, 0)
        XCTAssertNil(reloaded?.config.sampling.temperature)
        XCTAssertNil(reloaded?.config.sampling.contextWindow)
    }

    func testEditedConfigOverwritesInPlace() throws {
        let store = try SwiftDataStore(inMemory: true)
        var conversation = try store.createConversation(
            title: "Edited", mode: .remoteOnly, config: .default, isTemporary: false
        )
        conversation.config = configured
        try store.saveConversation(conversation)
        let reloaded = try store.conversation(id: conversation.id)
        XCTAssertEqual(reloaded?.config, configured, "an edit lands on the same row, not a new one")
    }

    /// A row written before P2 has `paramsJSON` and no configuration blob. Its knobs were mandatory,
    /// so they were asserted on every turn: they must come back as configured overrides. The
    /// injections stay off, because that chat never had them and adding them now would change answers
    /// inside a conversation the user already had.
    func testLegacyRowUpgradesToConfiguredOverrides() throws {
        let store = try SwiftDataStore(inMemory: true)
        let legacy = Data(
            """
            {"temperature":0.3,"topP":0.7,"repeatPenalty":1.2,"maxTokens":640,\
            "contextWindow":16384,"thinkingEnabled":true,"systemPrompt":"Old persona"}
            """
            .utf8
        )
        let id = UUID()
        let record = ConversationRecord(
            id: id, title: "Old chat", activeLeafID: nil,
            createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2),
            modeRaw: "remoteOnly", paramsJSON: legacy
        )
        store.context.insert(record)
        try store.context.save()

        let upgraded = try store.conversation(id: id)
        XCTAssertEqual(upgraded?.config.persona, "Old persona")
        XCTAssertEqual(upgraded?.config.sampling.temperature, 0.3)
        XCTAssertEqual(upgraded?.config.sampling.topP, 0.7)
        XCTAssertEqual(upgraded?.config.sampling.repeatPenalty, 1.2)
        XCTAssertEqual(upgraded?.config.sampling.maxTokens, 640)
        XCTAssertEqual(upgraded?.config.sampling.contextWindow, 16384)
        XCTAssertEqual(upgraded?.config.thinkingEnabled, true)
        XCTAssertEqual(upgraded?.config.context, .off, "an old chat gains no new injections")
        XCTAssertEqual(upgraded?.config.configuredOptionCount, 5)
    }

    func testAppSettingsSurviveAReload() throws {
        let store = try SwiftDataStore(inMemory: true)
        XCTAssertEqual(try store.appSettings(), .default, "no row reads as the shipped defaults")

        try store.saveAppSettings(
            AppSettings(defaultChatConfig: configured, themeID: "passage",
                        appearance: .dark, showsGenerationStats: false)
        )
        var stored = try store.appSettings()
        XCTAssertEqual(stored.defaultChatConfig, configured)
        XCTAssertEqual(stored.themeID, "passage")
        XCTAssertEqual(stored.appearance, .dark)
        XCTAssertEqual(stored.showsGenerationStats, false)

        // One row, not one per write: a second save must not create a second "the settings".
        stored.themeID = "trailhead"
        try store.saveAppSettings(stored)
        XCTAssertEqual(try store.appSettings().themeID, "trailhead")
        XCTAssertEqual(try store.appSettings().defaultChatConfig, configured)
    }

    /// The default seeds a new chat; it never reaches back into one that exists. Without this,
    /// changing a default would rewrite how an old conversation answers.
    func testDefaultConfigSeedsANewChatAndDoesNotFollowSettingsAfterwards() throws {
        let store = try SwiftDataStore(inMemory: true)
        let seeded = try store.createConversation(
            title: "Seeded", mode: .remoteOnly, config: configured, isTemporary: false
        )
        try store.saveAppSettings(.default)
        XCTAssertEqual(try store.conversation(id: seeded.id)?.config, configured)
        let fresh = try store.createConversation(
            title: "Fresh", mode: .remoteOnly, config: try store.appSettings().defaultChatConfig,
            isTemporary: false
        )
        XCTAssertEqual(fresh.config, .default)
    }
}

