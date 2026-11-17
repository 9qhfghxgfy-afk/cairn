import XCTest
import CairnChatDomain
@testable import CairnAppUI
@testable import CairnPersistence

/// The rules the per-chat configuration sheet runs on. The pixels belong to the sheet; what is pinned
/// here is what the sheet promises: the preview is the wire, a toggle really adds or removes a block, a
/// knob a server cannot read is named out loud, and "unset" survives.
@MainActor
final class ChatConfigSheetTests: XCTestCase {

    /// Deterministic environment, so the byte-for-byte comparison below is a comparison.
    private var environment: ContextEnvironment {
        ContextEnvironment(
            clock: .pinned(iso8601: "2026-11-17T09:00:00Z", timeZone: "UTC"),
            device: DeviceContext(platformName: "iOS", languageCode: "en", regionCode: "US")
        )
    }

    private var configured: ChatConfig {
        ChatConfig(
            persona: "Be terse.",
            sampling: SamplingConfig(temperature: 0.3, minP: 0.05, topK: 20, seed: .fixed(42)),
            context: ContextToggleSet(date: true, timeAndTimezone: false, platform: true),
            responseFormat: .terse
        )
    }

    /// The preview the sheet renders comes from the same call the stream uses, so what a user reads
    /// while moving a toggle is character for character what leaves the device.
    func testPreviewIsTheWireByteForByte() {
        let config = configured
        let preview = config.systemPrompt(in: environment, turn: .default)
        XCTAssertEqual(
            preview,
            ContextAssembly.assemble(
                persona: config.persona, toggles: config.context, format: config.responseFormat,
                environment: environment, turn: .default
            )
        )
        XCTAssertTrue(
            preview.hasPrefix("Be terse."),
            "the persona leads, so a line Cairn injects never re-frames it"
        )
        XCTAssertEqual(config.blocks(in: environment, turn: .default).joined(separator: "\n\n"), preview)
    }

    func testEverythingOffSendsNoSystemMessageAtAll() {
        XCTAssertEqual(
            ChatConfig.bare.systemPrompt(in: environment, turn: .default), "",
            "no persona and no toggles means no system turn, not an empty one"
        )
    }

    func testPersonaAloneSurvivesEveryToggleOff() {
        let config = ChatConfig(persona: "Only answer in haiku.", context: .off)
        XCTAssertEqual(config.systemPrompt(in: environment, turn: .default), "Only answer in haiku.")
    }

    /// A "use your tools" block on a turn with no tools teaches a model to claim an ability it was not
    /// given, so the toggle being on is not sufficient.
    func testConditionalBlocksAppearOnlyWhenTheFeatureIsLive() {
        var config = ChatConfig(persona: "Be terse.", context: ContextToggleSet.off)
        config.context.toolGuidance = true
        config.context.imageContext = true

        let bare = config.systemPrompt(in: environment, turn: .default)
        XCTAssertEqual(bare, "Be terse.", "no tools and no images means neither block is written")

        let withTools = TurnContext(toolsActive: true, toolNames: ["calculator"], imageCount: 2)
        XCTAssertNotEqual(config.systemPrompt(in: environment, turn: withTools), bare)
        XCTAssertTrue(ContextAssembly.isLive(.toolGuidance, turn: withTools))
        XCTAssertTrue(ContextAssembly.isLive(.imageContext, turn: withTools))
        XCTAssertFalse(ContextAssembly.isLive(.forceWebFetch, turn: withTools))
    }

    func testSheetNamesTheKeysTheServerWillDrop() {
        let config = configured
        let openAIStyle = ServerProfileKind.openAICompatible.samplingSupport
        XCTAssertEqual(config.unsupportedKeys(for: openAIStyle), [.minP, .topK])
        XCTAssertEqual(config.unsupportedKeys(for: .all), [])
        XCTAssertEqual(
            config.unsupportedKeys(for: .none),
            [.temperature, .seed, .minP, .topK],
            "an engine that declares nothing gets a warning about everything asserted"
        )
    }

    func testClearingAndResettingAreDistinctActions() {
        var draft = configured
        XCTAssertEqual(draft.configuredOptionCount, 4)

        draft.sampling = .unset
        XCTAssertEqual(draft.configuredOptionCount, 0)
        XCTAssertNil(draft.sampling.temperature)

        draft.reset(to: configured)
        XCTAssertEqual(draft, configured, "reset takes the baseline wholesale")

        draft.reset(to: .default)
        XCTAssertNil(draft.sampling.temperature, "a baseline that asserts nothing leaves nothing")
        XCTAssertEqual(draft.persona, "", "and it does not keep the old persona either")
    }

    /// Who owns the seed is a real distinction: Cairn choosing a number and the user typing one behave
    /// differently, and both are sent on every request so a replay reproduces.
    func testSeedControlOwnershipRules() {
        var draft = ChatConfig()
        draft.sampling.seed = .random(from: 1234)
        XCTAssertEqual(draft.sampling.seed?.mode, .random)

        draft.sampling.seed = draft.sampling.seed?.replacingSeed(with: 77)
        XCTAssertEqual(draft.sampling.seed, .random(from: 77), "randomize keeps the mode")

        draft.sampling.seed = .fixed(77)
        XCTAssertEqual(draft.sampling.seed?.mode, .fixed, "typing makes it the user's number")

        draft.sampling.clear(.seed)
        XCTAssertNil(draft.sampling.seed, "cleared means no seed key goes out at all")
    }

    /// The session's own preview — the one the sheet shows — must be the same call the config makes.
    func testSessionPreviewMatchesTheConfigsOwnCall() async throws {
        let store = try SwiftDataStore(inMemory: true)
        let workspace = ChatWorkspace(
            persistentStore: store,
            providers: [MockStreamingProvider.instant],
            mode: .onDeviceOnly,
            temporaryChat: false
        )
        await workspace.start()
        let session = try XCTUnwrap(workspace.session)
        session.updateConfig(configured)

        XCTAssertEqual(
            session.injectedContextPreview,
            session.conversation.config.systemPrompt(
                in: session.contextEnvironment, turn: session.currentTurnContext
            )
        )
        XCTAssertEqual(session.samplingSupport, .none, "the mock declares no knobs")
        XCTAssertEqual(try store.conversation(id: session.conversation.id)?.config, configured)
    }
}
