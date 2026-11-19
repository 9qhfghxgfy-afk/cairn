import Foundation
import XCTest
@testable import CairnChatDomain

/// The `Force Web Fetch` switch in the configuration sheet, followed all the way to the prompt.
///
/// This key shipped with its liveness hardcoded `false`, so the switch sat in the sheet moving a value
/// that nothing read and the block it promises was never written. The rule that replaces the constant is
/// the honest one: the block claims a web search ran for this turn, so it goes in when the user switched
/// it on **and** the turn really is being offered a web tool — and not otherwise.
@MainActor
final class WebFetchLivenessTests: XCTestCase {

    private static let blockLead = "A web search ran for this turn."

    private func session(
        tools: [any ToolExecuting],
        webToolsReleased: Bool,
        forceWebFetch: Bool
    ) throws -> ChatSessionModel {
        let store = EphemeralStore()
        var config = ChatConfig()
        config.toolToggle = .armed
        config.context.setValue(.forceWebFetch, forceWebFetch)
        let conversation = try store.createConversation(
            title: "New chat", mode: .onDeviceOnly, config: config, isTemporary: true
        )
        let model = ChatSessionModel(
            conversation: conversation, store: store, providers: [RecordingEngine()]
        )
        model.toolRegistry = ToolRegistry(tools: tools)
        model.outboundWebAllowed = webToolsReleased
        return model
    }

    private var webTools: [any ToolExecuting] {
        [CalculatorTool(), StubWebTool(name: BuiltInTool.webSearch)]
    }

    private var localOnlyTools: [any ToolExecuting] { [CalculatorTool()] }

    func testTheSwitchOnAWebTurnWritesTheBlock() throws {
        let model = try session(tools: webTools, webToolsReleased: true, forceWebFetch: true)
        XCTAssertTrue(
            model.injectedContextPreview.contains(Self.blockLead),
            "a switched-on Force Web Fetch has to reach the prompt it describes"
        )
    }

    func testTheSwitchOffWritesNoBlock() throws {
        let model = try session(tools: webTools, webToolsReleased: true, forceWebFetch: false)
        XCTAssertFalse(model.injectedContextPreview.contains(Self.blockLead))
    }

    /// A turn armed for the calculator only cannot be described by a block that says a web search ran.
    func testASwitchOnATurnWithoutAWebToolWritesNoBlock() throws {
        let model = try session(tools: localOnlyTools, webToolsReleased: true, forceWebFetch: true)
        XCTAssertFalse(
            model.injectedContextPreview.contains(Self.blockLead),
            "the block would describe a search this turn has no way to run"
        )
    }

    /// While the acknowledgement is down the web tool is withheld from the offer, so the switch describes
    /// a search that cannot happen — and the block has to stay out with it.
    func testASwitchWithheldWebToolWritesNoBlock() throws {
        let model = try session(tools: webTools, webToolsReleased: false, forceWebFetch: true)
        XCTAssertFalse(model.injectedContextPreview.contains(Self.blockLead))
    }

    /// The rule on its own, without a session in the way.
    func testTheRuleReadsTheSwitchAndTheOffer() {
        let web = ToolSelection(definitions: [
            ToolDefinition(name: BuiltInTool.webFetch, blurb: "Reads a page.", networkClass: .publicInternet),
        ])
        let local = ToolSelection(definitions: [
            ToolDefinition(name: BuiltInTool.calculator, blurb: "Evaluates an expression."),
        ])
        var on = ContextToggleSet()
        on.setValue(.forceWebFetch, true)

        XCTAssertTrue(ContextAssembly.webFetchIsLive(toggles: on, offered: web))
        XCTAssertFalse(ContextAssembly.webFetchIsLive(toggles: .off, offered: web))
        XCTAssertFalse(ContextAssembly.webFetchIsLive(toggles: on, offered: local))
        XCTAssertFalse(ContextAssembly.webFetchIsLive(toggles: on, offered: ToolSelection()))
    }

    /// The assembly side of the seam: the key is live exactly when the turn says a web tool ran.
    func testTheAssemblyFollowsTheTurnFlag() {
        XCTAssertTrue(
            ContextAssembly.isLive(.forceWebFetch, turn: TurnContext(webFetchActive: true))
        )
        XCTAssertFalse(
            ContextAssembly.isLive(.forceWebFetch, turn: TurnContext(webFetchActive: false))
        )
    }
}
